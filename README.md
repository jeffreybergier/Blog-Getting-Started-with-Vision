# Blog: Getting Started with Vision

## What is Vision?
Vision is a new framework from Apple for iOS 11 and other Apple platforms. Vision is a part of the [Core ML](https://developer.apple.com/machine-learning/) framework and they work hand in hand.

## Built-in Features
Vision has a number of built in features. Some of the things vision can do on still images, others on video, most on both.
    - Face Detection
        - Individual feature detection, such as nose, mouth, left eye, etc
    - Horizon detectionas
    - Rectangle detection
    - Character detection
    - Object tracking
    
## Getting Started with Object Tracking

### Project Overview
    - Start AVCaptureSession
    - Configure AVCaptureSession
    - Configure the Vision System.
    - Seed the vision system with an 'Observation' when the user taps the screen.
    - Update the rectangle on the screen as the vision system returns new 'Observations.'
    
### Start the AVCaptureSession

This is not new code so I'm not going to go into detail. We're going to add some lazy properties to our view controller. They just give us access to the `AVCaptureSession` as well as the `AVCaptureVideoPreviewLayer` so the user can see the video feed on the screen. The IBOutlet here is just a view that is the same width and height of the view controller's view. I did this so it was easy to put the red highlight view on top of the video output.

``` swift
    @IBOutlet private weak var cameraView: UIView?

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
        
        // make the camera appear on the screen
        self.cameraView?.layer.addSublayer(self.cameraLayer)
        
        // begin the session
        self.captureSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // make sure the layer is the correct size
        self.cameraLayer.frame = self.cameraView?.bounds ?? .zero
    }
```

At this point, you should be able to launch the app and see camera output on the screen.

### Configure AVCaptureSession

In order to get video buffers from the AVCaptureSession into the `VNSequenceRequestHandler` we need to tell the `AVCaptureSession` that we want to be a delegate of its video feed. In `viewDidLoad:` add the following code.

``` swift
    override func viewDidLoad() {
        // ...
        // make the camera appear on the screen...
        
        // register to receive buffers from the camera
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "MyQueue"))
        self.captureSession.addOutput(videoOutput)
        
        // begin the session...
    }
```

In order to receive the frames, we need to conform to the  `AVCaptureVideoDataOutputSampleBufferDelegate` and implement the appropriate method. Add a print statement into the method below and run the app. You should see that print statement be printed many times, repeatedly. The AVCaptureSession returns data often.

``` swift
class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { }
}
```

### Configure the Vision System

In this project, we're streaming video data into the vision system. This means that the Vision handler object is a long lived object in our view controller. So we're going to add another property for the `VNSequenceRequestHandler`.

``` swift
    private let visionSequenceHandler = VNSequenceRequestHandler()
```

The vision sequence system works in a loop. You provide a "seed" observation, then feed that into the vision system. The vision system then outputs a new observation. That new observation then needs to be fed back into the vision system when the camera has new data. In order to accomplish this, we need another property on our view controller. This property will store the seed observation. It will also store the observations returned by the vision system. Remember that the AVCaptureSession is creating the loop for us by calling the delegate method over and over.

``` swift
    private var lastObservation: VNDetectedObjectObservation?
```

In the `captureOutput:` method, we need to do a couple of things. We need to get the `CVPixelBuffer` out of the `CMSampleBuffer` that is passed in. We need to make sure we have an observation saved in the property we created in the above step. Then we need to create a `VNTrackObjectRequest`. Lastly, we need to ask the `VNSequenceRequestHandler` to process the request. Note that the request takes a completion handler and we have passed in `nil` for that. Thats OK. we're going to write tht completion handler late in the tutorial.

``` swift
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // make sure the pixel buffer can be converted
        // make sure that there is a previous observation we can feed into the request
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let lastObservation = self.lastObservation else { return }
        
        // create the request
        let request = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: nil)
        // set the accuracy to high
        // this is slower, but it works a lot better
        request.trackingLevel = .accurate
        
        // perform the request
        do {
            try self.visionSequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            print("Throws: \(error)")
        }
    }
```

### Seed the vision system with an 'Observation' when the user taps the screen.

When the user taps the screen, we want to find out where the user tapped, then pass that into the vision system as the seed observation. We also want to drop a red box around it so the user can see what we are tracking. In order to do this. Add an `@IBOutlet` property to your view controller for the Highlight View. Add a UIView into the Storyboard and wire it up to the outlet. Don't configure any autolayout on it because we will be managing its frame directly.

``` swift
    @IBOutlet private weak var highlightView: UIView? {
        didSet {
            self.highlightView?.layer.borderColor = UIColor.red.cgColor
            self.highlightView?.layer.borderWidth = 4
            self.highlightView?.backgroundColor = .clear
        }
    }
```

In order to the receive the tap, we're going to use a  `UITapGestureRecognizer` on the main view of the view controller. Once thats in the storyboard, wire it up to an `@IBAction` in the view controller. Below is the code to receive that tap from the gesture recognizer and then draw a red box around it using the Highlight view. Note that the size I picked is arbitrary. Pick any size you like. Also note that the rectangle we pass to the vision system is sensitive to the size and shape of the object to track. So if you could make the size of the red box, better match the object you want to track, the tracking will work better.

``` swift
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer) {
        // get the center of the tap
        self.highlightView?.frame.size = CGSize(width: 120, height: 120)
        self.highlightView?.center = sender.location(in: self.view)
    }
```

