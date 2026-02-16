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
    private var nowPlayingInfo: NowPlayingInfo?

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
    func activate() {
        guard !isActive else { return }
        isActive = true

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
        guard isActive else { return }
        updateNowPlayingInfo(isPlaying: isPlaying)
    }

    /// Updates the displayed info with new content details.
    /// - Parameter info: The new Now Playing information
    func update(info: NowPlayingInfo) {
        nowPlayingInfo = info
        if isActive {
            updateNowPlayingInfo(isPlaying: true)
        }
    }
    
    /// Reconfigures the audio session to ensure we remain the Now Playing app.
    /// Call this when switching between different audio sources (e.g., local to remote voice).
    func reconfigureAudioSession() {
        guard isActive else { return }
        setupAudioSession()
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

        // Skip forward command
        skipForwardCommandTarget = commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.forwardHandler?()
            return .success
        }
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]

        // Skip backward command
        skipBackwardCommandTarget = commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.backwardHandler?()
            return .success
        }
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        // Disable unsupported commands
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
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
            MPMediaItemPropertyTitle: nowPlayingInfo?.title ?? L10n.Accessibility.Speech.title,
            MPMediaItemPropertyMediaType: MPMediaType.anyAudio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let currentText = nowPlayingInfo?.currentText {
            info[MPMediaItemPropertyArtist] = currentText
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
