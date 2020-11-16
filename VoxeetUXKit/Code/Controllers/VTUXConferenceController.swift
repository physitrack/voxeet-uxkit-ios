//
//  VTUXConferenceController.swift
//  VoxeetUXKit
//
//  Created by Corentin Larroque on 05/08/2019.
//  Copyright © 2019 Voxeet. All rights reserved.
//

import VoxeetSDK

@objc public class VTUXConferenceController: NSObject {
    private var viewController: ConferenceViewController?
    
    private var currentStatus: VTConferenceStatus?
    private var previousStatus: VTConferenceStatus?
    
    /// Conference configuration.
    @objc public var configuration = VTUXConferenceControllerConfiguration()
    
    /// Conference appear animation default starts maximized. If false, the conference will appear minimized.
    @objc public var appearMaximized = true
    
    /// If true, the conference will behave like a cellular call. if a participant hangs up or declines a call, the caller will be disconnected.
    @objc public var telecom = false {
        didSet {
            if telecom {
                NotificationCenter.default.addObserver(self, selector: #selector(participantUpdated), name: .VTParticipantUpdated, object: nil)
            } else {
                NotificationCenter.default.removeObserver(self, name: .VTParticipantUpdated, object: nil)
            }
        }
    }
    
    public override init() {
        super.init()
        
        // Voxeet's socket notifications.
        NotificationCenter.default.addObserver(self, selector: #selector(ownParticipantSwitched), name: .VTOwnParticipantSwitched, object: nil)
        // Conference status notifications.
        NotificationCenter.default.addObserver(self, selector: #selector(conferenceStatusUpdated), name: .VTConferenceStatusUpdated, object: nil)
    }
}

/*
 *  MARK: - Notifications: Voxeet
 */

extension VTUXConferenceController {
    @objc private func participantUpdated(notification: NSNotification) {
        // Get JSON.
        guard let userInfo = notification.userInfo?.values.first as? Data else { return }
        
        // Debug.
        print("[VoxeetUXKit] \(String(describing: VoxeetUXKit.self)).\(#function).\(#line)")
        
        // Stop conference if a participant declines or leaves it.
        if let json = try? JSONSerialization.jsonObject(with: userInfo, options: .mutableContainers) {
            if let jsonDict = json as? [String: Any], let status = jsonDict["status"] as? String, status == "DECLINE" || status == "LEFT" {
                // Update conference state label.
                if status == "DECLINE" {
                    self.viewController?.conferenceStateLabel.text = VTUXLocalized.string("VTUX_CONFERENCE_STATE_DECLINED")
                }
                
                // Leave current conference.
                VoxeetSDK.shared.conference.leave()
            }
        }
    }
    
    @objc private func ownParticipantSwitched(notification: NSNotification) {
        // Debug.
        print("[VoxeetUXKit] \(String(describing: VoxeetUXKit.self)).\(#function).\(#line)")
        
        // Stop the current conference.
        VoxeetSDK.shared.conference.leave()
    }
}

/*
 *  MARK: - Notifications: conference status
 */

extension VTUXConferenceController {
    @objc private func conferenceStatusUpdated(notification: NSNotification) {
        guard let status = notification.userInfo?["status"] as? VTConferenceStatus else {
            return
        }
        // Save current conference status.
        currentStatus = status
        
        switch status {
        case .creating, .joining:
            // Properly remove the viewController from superview when joining if the previous conference status wasn't the one expected (`created`).
            if status == .joining && previousStatus != .created {
                // Remove conference view from superview.
                self.viewController?.view.removeFromSuperview()
                self.viewController = nil
            }
            
            // Create and show conference view.
            if viewController == nil {
                // Create conference UI and adds it to the window.
                let storyboard = UIStoryboard(name: "VoxeetUXKit", bundle: Bundle(for: type(of: self)))
                viewController = storyboard.instantiateInitialViewController() as? ConferenceViewController
                if let vc = viewController {
                    vc.view.translatesAutoresizingMaskIntoConstraints = false
                    guard let window = UIApplication.shared.keyWindow else { return }
                    window.addSubview(vc.view)
                }
                
                // Show conference.
                if appearMaximized {
                    viewController?.show()
                } else {
                    viewController?.view.alpha = 0
                    viewController?.minimize(animated: false)
                    UIView.animate(withDuration: 0.25) {
                        self.viewController?.view.alpha = 1
                    }
                }
            }
        case .left, .destroyed, .error:
            // Hide conference.
            viewController?.hide {
                // Only remove the viewController from superview if the initial operation was intended for (during the hidding animation, another conference could be joined and we shouldn't call the code below in that case).
                if self.currentStatus == .left || self.currentStatus == .destroyed || self.currentStatus == .error {
                    // Remove conference view from superview.
                    self.viewController?.view.removeFromSuperview()
                    self.viewController = nil
                }
            }
        default: break
        }
        
        // Update conference UI.
        viewController?.updateConferenceStatus(status)
        
        // Save previous conference status.
        previousStatus = status
    }
}
