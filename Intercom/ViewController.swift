import UIKit
import MultipeerConnectivity
import AVFoundation

class ViewController: UIViewController, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, AVAudioRecorderDelegate {
    private let serviceType = "voice-intercom"
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupConnectivity()
        setupAudioEngine()
    }
    
    private func setupConnectivity() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        audioEngine.attach(audioPlayerNode)
        
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    @IBAction func toggleIntercom(_ sender: UIButton) {
        if audioRecorder == nil {
            startRecording()
        } else {
            stopRecording()
        }
    }
    
    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
            
            let url = URL(fileURLWithPath: "/dev/null")
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                if let recorder = self.audioRecorder, recorder.isRecording {
                    recorder.updateMeters()
                    let data = recorder.peakPower(forChannel: 0)
                    self.sendAudioData(data)
                } else {
                    timer.invalidate()
                }
            }
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
    }
    
    private func sendAudioData(_ data: Float) {
        guard let session = session else { return }
        
        var mutableData = data
        let audioData = Data(bytes: &mutableData, count: MemoryLayout.size(ofValue: mutableData))
        
        do {
            try session.send(audioData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Failed to send audio data: \(error)")
        }
    }
    
    // MCSessionDelegate methods
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Handle state changes
        switch state {
        case .connected:
            print("Connected to peer: \(peerID.displayName)")
        case .notConnected:
            print("Disconnected from peer: \(peerID.displayName)")
        case .connecting:
            print("Connecting to peer: \(peerID.displayName)")
        @unknown default:
            fatalError()
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle received data
        let audioData = data.withUnsafeBytes {
            $0.load(as: Float.self)
        }
        playAudioData(audioData)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    
    // MCNearbyServiceAdvertiserDelegate methods
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    // MCNearbyServiceBrowserDelegate methods
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    
    private func playAudioData(_ data: Float) {
        let buffer = AVAudioPCMBuffer(pcmFormat: audioEngine.mainMixerNode.outputFormat(forBus: 0), frameCapacity: AVAudioFrameCount(44100 * 0.05))
        buffer?.frameLength = buffer!.frameCapacity
        
        let channels = UnsafeBufferPointer(start: buffer?.floatChannelData, count: Int(buffer!.format.channelCount))
        for frame in 0..<Int(buffer!.frameLength) {
            channels[0][frame] = data
        }
        
        audioPlayerNode.scheduleBuffer(buffer!, completionHandler: nil)
        audioPlayerNode.play()
    }
}
