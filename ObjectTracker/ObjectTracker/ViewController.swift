//
//  ViewController.swift
//  ObjectTracker
//
//  Created by Jeffrey Bergier on 6/8/17.
//  Copyright © 2017 Saturday Apps. All rights reserved.
//

import AVFoundation
import Vision
import UIKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet private weak var cameraView: UIView?
    @IBOutlet private weak var highlightView: UIView? {
        didSet {
            self.highlightView?.layer.borderColor = UIColor.red.cgColor
            self.highlightView?.layer.borderWidth = 4
            self.highlightView?.backgroundColor = .clear
        }
    }
    
    private let visionSequenceHandler = VNSequenceRequestHandler()
    private lazy var cameraLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        do {
            guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return session }
            let input = try AVCaptureDeviceInput(device: backCamera)
            session.addInput(input)
        } catch {
            print("Error Loading Camera: \(error)")
        }
        return session
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // hide the red focus area on load
        self.highlightView?.frame = .zero
        
        // make the camera appear on the screen
        self.cameraView?.layer.addSublayer(self.cameraLayer)
        
        // register to receive buffers from the camera
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "MyQueue"))
        self.captureSession.addOutput(videoOutput)
        
        // begin the session
        self.captureSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // make sure the layer is the correct size
        self.cameraLayer.frame = self.view.bounds
    }
    
    private var lastObservation: VNDetectedObjectObservation?
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let previousObservation = self.lastObservation else { return }
        let request = VNTrackObjectRequest(detectedObjectObservation: previousObservation) { request, error in
            DispatchQueue.main.async(execute: { self.handleVisionRequestUpdate(request, error: error) })
        }
        do {
            try self.visionSequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            print("Throws: \(error)")
        }
    }
    
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // make sure we have an actual result
        guard let newObservation = request.results?.first as? VNDetectedObjectObservation else { print(error!); return }
        
        // prepare for next loop
        self.lastObservation = newObservation
        
        // check the confidence level before updating the UI
        guard newObservation.confidence >= 0.9 else { return }
        
        // calculate view rect
        var transformedRect = newObservation.boundingBox
        transformedRect.origin.y = 1 - transformedRect.origin.y
        let convertedRect = self.cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
        
        // move the highlight view
        self.highlightView?.frame = convertedRect
    }
    
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer) {
        // get the center of the tap
        self.highlightView?.frame.size = CGSize(width: 120, height: 120)
        self.highlightView?.center = sender.location(in: self.view)
        
        // convert the rect for the initial observation
        var convertedRect = self.cameraLayer.metadataOutputRectConverted(fromLayerRect: self.highlightView?.frame ?? .zero)
        convertedRect.origin.y = 1 - convertedRect.origin.y
        let newObservation = VNDetectedObjectObservation(boundingBox: convertedRect)
        
        // set the observation
        self.lastObservation = newObservation
    }
    
    @IBAction private func resetTapped(_ sender: UIBarButtonItem) {
        self.lastObservation = nil
        self.highlightView?.frame = .zero
    }
}

