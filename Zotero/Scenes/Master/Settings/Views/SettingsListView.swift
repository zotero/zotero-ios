//
//  SettingsListView.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI

struct SettingsListView: View {
    weak var coordinatorDelegate: SettingsCoordinatorDelegate?

    var body: some View {
        Form {
            Section(header: Text("")) {
                Button(action: {
                    self.coordinatorDelegate?.showAboutBeta()
                }, label: {
                    Text(L10n.aboutBeta)
                        .foregroundColor(Color(self.textColor))
                })
            }

            Section {
                NavigationLink(destination: ProfileView()) {
                    Text(L10n.Settings.account)
                }
            }

            Section {
                NavigationLink(destination: GeneralSettingsView()) {
                    Text(L10n.Settings.General.title)
                }

                Button(action: {
                    self.coordinatorDelegate?.showCitationSettings()
                }, label: {
                    Text(L10n.Settings.Cite.title)
                        .foregroundColor(Color(self.textColor))
                })

                NavigationLink(destination: SavingSettingsView()) {
                    Text(L10n.Settings.Saving.title)
                }

                NavigationLink(destination: StorageSettingsView()) {
                    Text(L10n.Settings.storage)
                }

                NavigationLink(destination: DebugSettingsView()) {
                    Text(L10n.Settings.debug)
                }
            }

            Section {
                Button(action: {
                    self.coordinatorDelegate?.showSupport()
                }, label: {
                    Text(L10n.supportFeedback)
                        .foregroundColor(Color(self.textColor))
                })

                Button(action: {
                    self.coordinatorDelegate?.showPrivacyPolicy()
                }, label: {
                    Text(L10n.privacyPolicy)
                        .foregroundColor(Color(self.textColor))
                })
            }
        }
        .padding(.top, -30)
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text(L10n.Settings.title), displayMode: .inline)
        .navigationBarItems(leading: Button(action: { self.coordinatorDelegate?.dismiss() },
                                            label: { Text(L10n.close).padding(.vertical, 10).padding(.trailing, 10) }))
    }

    private var textColor: UIColor {
        return UIColor(dynamicProvider: { traitCollection -> UIColor in
            return traitCollection.userInterfaceStyle == .dark ? .white : .black
        })
    }
}

struct SettingsListView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsListView()
    }
}
