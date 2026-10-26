//
//  NowPlayingManager.swift
//  Zotero
//
//  Created by Michal Rentka on 16.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import AVFoundation
import MediaPlayer
import UIKit

import CocoaLumberjackSwift

/// Manages Now Playing info and remote command center for text-to-speech playback.
/// This enables media key support (play/pause, forward, backward) on devices with external keyboards,
/// headphones, and the lock screen controls.
final class NowPlayingManager {
    struct NowPlayingInfo {
        let title: String
        let artist: String?
        let currentText: String?
    }

    private var playCommandTarget: Any?
    private var pauseCommandTarget: Any?
    private var togglePlayPauseCommandTarget: Any?
    private var nextTrackCommandTarget: Any?
    private var previousTrackCommandTarget: Any?
    private var skipForwardCommandTarget: Any?
    private var skipBackwardCommandTarget: Any?

    private var isActive = false
    private var isPlaying = false
    /// Keeps audio output running between sentences, see `SilentAudioPlayer`.
    private let silentAudioPlayer = SilentAudioPlayer()
    private var nowPlayingInfo: NowPlayingInfo?
    /// Cover of the document, shown as artwork on the lock screen, in Control Center and in CarPlay.
    private var artwork: MPMediaItemArtwork?

    var playPauseHandler: (() -> Void)?
    var forwardHandler: (() -> Void)?
    var backwardHandler: (() -> Void)?

    init() {}

    deinit {
        deactivate()
    }

    // MARK: - Public API

    /// Activates the Now Playing session and registers for remote command events.
    /// Call this when speech playback starts.
    /// - Parameter title: The document title to display on the lock screen.
    /// - Parameter artist: The document authors to display with the title.
    /// - Parameter artwork: The document cover to display with the title.
    func activate(title: String? = nil, artist: String? = nil, artwork: UIImage? = nil) {
        guard !isActive else { return }
        isActive = true
        isPlaying = false

        if let title {
            nowPlayingInfo = NowPlayingInfo(title: title, artist: artist, currentText: nil)
        }
        self.artwork = artwork.flatMap(Self.createArtwork(from:))

        setupAudioSession()
        setupRemoteCommandCenter()
        updateNowPlayingInfo(isPlaying: false)

        // Begin receiving remote control events - may be needed for some accessories
        UIApplication.shared.beginReceivingRemoteControlEvents()

        DDLogInfo("NowPlayingManager: activated")
    }

    /// Deactivates the Now Playing session and removes remote command handlers.
    /// Call this when speech playback stops completely.
    func deactivate() {
        guard isActive else { return }
        isActive = false

        isPlaying = false
        silentAudioPlayer.stop()
        UIApplication.shared.endReceivingRemoteControlEvents()
        removeRemoteCommandHandlers()
        clearNowPlayingInfo()
        deactivateAudioSession()

        DDLogInfo("NowPlayingManager: deactivated")
    }

    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            DDLogError("NowPlayingManager: failed to deactivate audio session - \(error)")
        }
    }

    /// Updates the Now Playing state to reflect current playback status.
    /// - Parameter isPlaying: Whether speech is currently playing
    func updatePlaybackState(isPlaying: Bool) {
        // Speech reports its state with each sentence. Unchanged state isn't written again, so that the system doesn't
        // refresh the controls with each sentence.
        guard isActive, isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        if isPlaying {
            silentAudioPlayer.start()
        } else {
            silentAudioPlayer.stop()
        }
        updateNowPlayingInfo(isPlaying: isPlaying)
    }

    /// Updates the displayed artwork, e.g. once the document cover has been generated.
    /// - Parameter artwork: The document cover to display with the title.
    func update(artwork: UIImage?) {
        self.artwork = artwork.flatMap(Self.createArtwork(from:))
        if isActive {
            updateNowPlayingInfo(isPlaying: isPlaying)
        }
    }

    /// Updates the displayed info with new content details.
    /// - Parameter info: The new Now Playing information
    func update(info: NowPlayingInfo) {
        nowPlayingInfo = info
        if isActive {
            updateNowPlayingInfo(isPlaying: isPlaying)
        }
    }

    /// Reconfigures the audio session to ensure we remain the Now Playing app.
    /// Call this when switching between different audio sources (e.g., local to remote voice).
    func reconfigureAudioSession() {
        guard isActive else { return }
        setupAudioSession()
        if isPlaying {
            silentAudioPlayer.start()
        }
        DDLogInfo("NowPlayingManager: audio session reconfigured")
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .playback category without options to properly interrupt other audio and become the Now Playing app
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true, options: [])
            DDLogInfo("NowPlayingManager: audio session configured")
        } catch {
            DDLogError("NowPlayingManager: failed to configure audio session - \(error)")
        }
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Play command
        playCommandTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            DDLogInfo("NowPlayingManager: play command received")
            self?.playPauseHandler?()
            return .success
        }
        commandCenter.playCommand.isEnabled = true

        // Pause command
        pauseCommandTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            DDLogInfo("NowPlayingManager: pause command received")
            self?.playPauseHandler?()
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true

        // Toggle play/pause command (for media keys)
        togglePlayPauseCommandTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            DDLogInfo("NowPlayingManager: toggle play/pause command received")
            self?.playPauseHandler?()
            return .success
        }
        commandCenter.togglePlayPauseCommand.isEnabled = true

        // Next track command (for forward navigation)
        nextTrackCommandTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.forwardHandler?()
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true

        // Previous track command (for backward navigation)
        previousTrackCommandTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.backwardHandler?()
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true

        // Disable unsupported commands
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    private func removeRemoteCommandHandlers() {
        let commandCenter = MPRemoteCommandCenter.shared()

        if let target = playCommandTarget {
            commandCenter.playCommand.removeTarget(target)
        }
        if let target = pauseCommandTarget {
            commandCenter.pauseCommand.removeTarget(target)
        }
        if let target = togglePlayPauseCommandTarget {
            commandCenter.togglePlayPauseCommand.removeTarget(target)
        }
        if let target = nextTrackCommandTarget {
            commandCenter.nextTrackCommand.removeTarget(target)
        }
        if let target = previousTrackCommandTarget {
            commandCenter.previousTrackCommand.removeTarget(target)
        }
        if let target = skipForwardCommandTarget {
            commandCenter.skipForwardCommand.removeTarget(target)
        }
        if let target = skipBackwardCommandTarget {
            commandCenter.skipBackwardCommand.removeTarget(target)
        }
        playCommandTarget = nil
        pauseCommandTarget = nil
        togglePlayPauseCommandTarget = nil
        nextTrackCommandTarget = nil
        previousTrackCommandTarget = nil
        skipForwardCommandTarget = nil
        skipBackwardCommandTarget = nil
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo(isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingInfo?.title ?? L10n.Speech.title,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let artist = nowPlayingInfo?.currentText ?? nowPlayingInfo?.artist {
            info[MPMediaItemPropertyArtist] = artist
        }

        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // Set explicitly, so that the system (e.g. CarPlay) doesn't derive the state from audio session activity, which doesn't
        // match speech playback.
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    /// The request handler can be called on a background queue, so it only captures the image.
    private static func createArtwork(from image: UIImage) -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

/// Plays silence while speech is playing.
///
/// On iOS the system (lock screen, Control Center, CarPlay) derives the play/pause state of Now Playing from whether the app
/// actually outputs audio, `MPNowPlayingInfoCenter.playbackState` isn't respected. Speech is played sentence by sentence
/// (a new `AVAudioPlayer` for each remote voice segment, a new utterance for each paragraph of local voice), with short
/// silent gaps (voice sentence delay, segment loading) in between. During these gaps no audio is output and the system
/// briefly shows the paused state. Silence played continuously keeps the output running, so the state stays "playing".
private final class SilentAudioPlayer {
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat?
    private var buffer: AVAudioPCMBuffer?
    private var isConfigured: Bool
    private var shouldPlay: Bool
    private var configurationObserver: NSObjectProtocol?

    init() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        isConfigured = false
        shouldPlay = false
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        player.stop()
        engine.stop()
    }

    func start() {
        shouldPlay = true
        play()
    }

    func stop() {
        shouldPlay = false
        player.stop()
        engine.stop()
    }

    private func play() {
        guard configureIfNeeded(), let buffer else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            if !player.isPlaying {
                player.scheduleBuffer(buffer, at: nil, options: .loops)
                player.play()
            }
        } catch let error {
            DDLogError("SilentAudioPlayer: can't start - \(error)")
        }
    }

    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
            DDLogError("SilentAudioPlayer: can't create buffer")
            return false
        }
        // Buffer contents aren't guaranteed to be zeroed.
        buffer.frameLength = buffer.frameCapacity
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
            }
        }
        self.buffer = buffer

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // The engine stops itself when the audio route changes (e.g. connecting to CarPlay or headphones).
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, shouldPlay else { return }
            player.stop()
            play()
        }
        isConfigured = true
        return true
    }
}
