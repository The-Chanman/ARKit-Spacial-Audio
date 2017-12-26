//
//  Recorder.swift
//  Audio in ARKit
//
//  Created by Eric Chan on 12/21/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import AVFoundation

protocol RecordAndPlayManagerDelegate : class{
    func recorderDidStopRecording()
}

class RecordAndPlayManager: NSObject, AVAudioRecorderDelegate {
    var soundRecorder: AVAudioRecorder!
    let recordSettings = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 12000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    class func directoryURL() -> URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as URL
        let soundURL = documentDirectory.appendingPathComponent("recording.m4a")
        return soundURL
    }
    
    //calling this from outside to get the audio
    class func getLocalOrRemoteRecording(_ recordingID : String!) -> URL?{
        
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as URL
        let soundURL = documentDirectory.appendingPathComponent(recordingID)
        
        if (fileManager.fileExists(atPath: soundURL.path)){
            return soundURL
        }
        
        let path = kBaseServerURLNOPORT + "data/" + recordingID
        let url = URL(string: path)
        
        return url
        
    }
    
    //called from outside, recordingID -> name of the file
    class func storeRecording(_ recordingID : String!) -> URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentDirectory = urls[0] as URL
        let soundURL = documentDirectory.appendingPathComponent("recording.m4a")
        
        let data = try? Data(contentsOf: soundURL)
        //data here has only 28bytes and from this I know it didn't record. In my tests, I always get at least 20000 bytes.
        
        let newSoundURL = documentDirectory.appendingPathComponent(recordingID)
        try? data?.write(to: newSoundURL, options: [.atomic])
        
        do {
            try  FileManager.default.removeItem(at: soundURL)
        } catch _ {
            print("failed to delete file")
            return newSoundURL
        }
        
        return newSoundURL
    }
    
    //called on viewDidLoad in another screen
    func setupRecorder() {
        let url = DRMessageRecordAndPlayManager.directoryURL()!
        do {
            try self.soundRecorder = AVAudioRecorder(url: url, settings: self.recordSettings)
        } catch _ {
            return
        }
        soundRecorder.delegate = self
        soundRecorder.prepareToRecord()
    }
    
    //calling this from outside to start recording
    func startRecording() {
        if !self.soundRecorder.isRecording {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
                try audioSession.setActive(true)
                soundRecorder.record(forDuration: 15)
            } catch {
            }
        }
    }
    
    //called from outside when I hit stop
    func stopRecording() {
        
        self.soundRecorder.stop()
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(false)
        } catch {
        }
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        self.delegate?.recorderDidStopRecording()
    }
}
