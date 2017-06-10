# Blog: Getting Started with Vision

## What is Vision?
Vision is a new framework from Apple for iOS 11 and other Apple platforms. Vision is a part of the [Core ML](https://developer.apple.com/machine-learning/) framework. CoreML is the new framework that makes it really easy to take a machine learning model and run your data through it to get predictions. The Vision framework helps you feed machine learning models that expect images. Using the Vision framework, its really easy to process a live feed from the camera and extract information from each frame using both built in and external machine learning models.

## Built-in Features
Vision has a number of built in features. Some of the things vision can do on still images, others on video, most on both.

   - Face Detection
      - Individual feature detection, such as nose, mouth, left eye, etc
   - Horizon detection
   - Rectangle detection
   - Character detection
   - Object tracking
   - Object recognition
      - via external machine learning models.
    
## Getting Started with Object Tracking

We're going to build a simple project where the user taps on an object on the screen and then the Vision system is going to track that object. As the user moves the phone, we would expet the object to be tracked in the video frame. Also, if the object moves on its own, it should be tracked by the Vision framework. 

Note that the code below does not represent best practices in terms of reducing the complexity of your view controllers. Its just an easy place to get started. Ideally, you would abstract most of this code into a custom object that the view controller uses.

Also note, this tutorial assumes you are comfortable with the basics of storyboards to hook up basic views and gesture recgonizers.

### Project Overview
   1. Start AVCaptureSession
   1. Configure AVCaptureSession
   1. Configure the vision system.
   1. Seed the vision system with an 'Observation' when the user taps the screen.
   1. Update the rectangle on the screen as the vision system returns new 'Observations.'
    
### 1. Start the AVCaptureSession

This is not new code so I'm not going to go into detail. We're going to add some lazy properties to our view controller. They just give us access to the `AVCaptureSession` as well as the `AVCaptureVideoPreviewLayer` so the user can see the video feed on the screen. The IBOutlet here is just a view that is the same width and height of the view controller's view. I did this so it was easy to put the Highlight view on top of the video output.

At this point, you should be able to launch the app and see camera output on the screen.

``` swift
class ViewController: UIViewController {

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
}
```

### 2. Configure AVCaptureSession

In order to get video buffers from the AVCaptureSession into the vision system we need to tell the `AVCaptureSession` that we want to be a delegate of its video feed. In `viewDidLoad:` add the following code.

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

In order to receive the frames, we need to conform to the  `AVCaptureVideoDataOutputSampleBufferDelegate` and implement the appropriate method. 

Add a print statement into the method below and run the app. You should see the console grow rapidly. The AVCaptureSession returns data often.

``` swift
class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { }
}
```

### 3. Configure the Vision System

In this project, we're streaming video data into the vision system. This means that the Vision handler object is a long lived object in our view controller. So we're going to add another property for the `VNSequenceRequestHandler`.

``` swift
    private let visionSequenceHandler = VNSequenceRequestHandler()
```

The vision sequence system works in a loop. You provide a "seed" observation, then feed that into the vision system. The vision system then outputs a new observation. That new observation then needs to be fed back into the vision system when the camera has new data. In order to accomplish this, we need another property on our view controller. This property will store the seed observation. It will also store the observations returned by the vision system. Remember that the AVCaptureSession is creating the loop for us by calling the delegate method over and over.

``` swift
    private var lastObservation: VNDetectedObjectObservation?
```

In the `captureOutput:didOutput:from:` method, we need to do a few things:

   1. We need to get the `CVPixelBuffer` out of the `CMSampleBuffer` that is passed in. 
   1. We need to make sure we have an observation saved in the property we created in the above step. 
   1. Then we need to create and configure a `VNTrackObjectRequest`. 
   1. Lastly, we need to ask the `VNSequenceRequestHandler` to perform the request. 
   
Note that the request takes a completion handler and we have passed in `nil` for that. Thats OK. we're going to write the completion handler later in the tutorial.

``` swift
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard
            // get the CVPixelBuffer out of the CMSampleBuffer
            let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            // make sure that there is a previous observation we can feed into the request
            let lastObservation = self.lastObservation
        else { return }
        
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

### 4. Seed the vision system with an 'Observation' when the user taps the screen.

When the user taps the screen, we want to find out where the user tapped, then pass that into the vision system as the seed observation. We also want to draw a red box around it so the user can see what we are tracking. In order to do this. Add an `@IBOutlet` property to your view controller for the Highlight View. Add a UIView into the Storyboard and wire it up to the outlet. Don't configure any autolayout on it because we will be managing its frame directly.

``` swift
    @IBOutlet private weak var highlightView: UIView? {
        didSet {
            self.highlightView?.layer.borderColor = UIColor.red.cgColor
            self.highlightView?.layer.borderWidth = 4
            self.highlightView?.backgroundColor = .clear
        }
    }
```

In order to the receive the tap, we're going to use a  `UITapGestureRecognizer` on the main view of the view controller. Once thats in the storyboard, wire it up to an `@IBAction` in the view controller. Below is the code to receive that tap from the gesture recognizer and then draw a red box around it using the Highlight view.

Note that the size I picked is arbitrary. Also note that the Vision system is sensitive to the width and height of the rectangle we pass in. The closer the rectangle surrounds the object, the better the Vision system will be able to track it.

``` swift
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer) {
        // get the center of the tap
        self.highlightView?.frame.size = CGSize(width: 120, height: 120)
        self.highlightView?.center = sender.location(in: self.view)
    }
```

Unfortunately, we can't pass this CGRect directly into the Vision system. There are 3 different coordinate systems we have to convert between. 
   1. UIKit coordinate space
      - Origin in the top left corner
      - Max height and width values of the screen size in points (320 x 560 on a 4in iPhone)
   1. AVFoundation coordinate space
      - Origin in the top left
      - Max height and width of 1
   1. Vision coordinate space
      - Origin in the bottom left
      - Max height and width of 1
      
Luckily, the `AVCaptureVideoPreviewLayer` has helper methods that convert between UIKit coordinates and AVFoundation coordinates. Once we have AVFoundation values, we can invert the Y origin to convert to Vision coordinate.

``` swift
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer) {
        // get the center of the tap
        // ..
        
        // convert the rect for the initial observation
        let originalRect = self.highlightView?.frame ?? .zero
        var convertedRect = self.cameraLayer.metadataOutputRectConverted(fromLayerRect: originalRect)
        convertedRect.origin.y = 1 - convertedRect.origin.y
    }
```

Once we have the correct CGRect to pass to the vision system, we can create our seed observation and store it in the property we created earlier.

``` swift
    @IBAction private func userTapped(_ sender: UITapGestureRecognizer) {
        // ..
        // convert the rect for the initial observation
        // ..
        
        // set the observation
        let newObservation = VNDetectedObjectObservation(boundingBox: convertedRect)
        self.lastObservation = newObservation
    }
```

Now if you run the app and tap the screen, you should see a red box appear around where you touched. Also, unknown to you, the vision system is running and it is performing object tracking. However, we never added the completion handler to our request. So the results of the object tracking are not doing anything.

### 5. Update the rectangle on the screen as the vision system returns new 'Observations.'

We're going to add a new method to the view controller. We'll use this method as the completion handler for our object tracking request.

``` swift
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        DispatchQueue.main.async {
        }
    }
```

Make sure to adjust the request object to take this method as a completion handler

``` swift
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // ..
        // create the request
        let request = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: self.handleVisionRequestUpdate)
        //..
    }
```

In the completion handler, there are 3 things we need to do:

   1. Check that the observation object is the correct kind of observation.
   1. Replace the `lastObservation` property with the new observation.
      - That way its ready next time the camera has a new frame for us. 
   1. Update the UI to draw the Highlight view around the new observation. This way the user can see the tracking as it happens.

Below, is the guard statement that allows us to check we have the correct observation type and store it in our property for next time.

``` swift
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        DispatchQueue.main.async {
            // make sure we have an actual result
            guard let newObservation = request.results?.first as? VNDetectedObjectObservation else { return }
            
            // prepare for next loop
            self.lastObservation = newObservation
        }
    }
```

Now we need to take the `boundingBox` of the observation and convert it from Vision space to UIKit space. To do this, we do the opposite of what we did in the tap gesture `@IBAction`. We take the original, flip the y coordinate to convert to AVFoundation coordinates. Then we use the `AVCaptureVideoPreviewLayer` to convert from AVFoundation coordinates to UIKit coordinates. Then we set the frame on the Highlight view.

``` swift
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        DispatchQueue.main.async {
            // ..
            // prepare for next loop
            // ..
            
            // calculate view rect
            var transformedRect = newObservation.boundingBox
            transformedRect.origin.y = 1 - transformedRect.origin.y
            let convertedRect = self.cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
            
            // move the highlight view
            self.highlightView?.frame = convertedRect
        }
    }
```

Now when you run the app, you can tap on something and you should be able to slowly pan the phone and see the red Highlight view stay on that object. To add a tiny amount of polish, we can check the `confidence` property on the observation. This property tells us how confident the model is about whether its the correct object being tracked or not. Confidence is a value between 0 and 1. In my testing, 0.3 seemed to be about the cut off where things were getting bad. Here is the final completion handler:

``` swift
    private func handleVisionRequestUpdate(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        DispatchQueue.main.async {
            // make sure we have an actual result
            guard let newObservation = request.results?.first as? VNDetectedObjectObservation else { return }
            
            // prepare for next loop
            self.lastObservation = newObservation
            
            // check the confidence level before updating the UI
            guard newObservation.confidence >= 0.3 else {
                // hide the rectangle when we lose accuracy so the user knows something is wrong
                self.highlightView?.frame = .zero
                return
            }
            
            // calculate view rect
            var transformedRect = newObservation.boundingBox
            transformedRect.origin.y = 1 - transformedRect.origin.y
            let convertedRect = self.cameraLayer.layerRectConverted(fromMetadataOutputRect: transformedRect)
            
            // move the highlight view
            self.highlightView?.frame = convertedRect
        }
    }
```

## Summary

Now you have a working object tracker working with a live video feed. Note that the techniques we used here work with almost all of the Vision framework request types. You use the AVCaptureSession delegate callbacks to feed new `CVPixelBuffer`s and new requests to the `VNSequenceRequestHandler`.

Also note that you can compose the requests. The request handler takes an Array of request objects. So you can make several of them that all do different things and pass them into the request handler. Two primary use cases come to mind for why you would want to do this.

   1. Use the `VNDetectFaceRectanglesRequest` object to detect faces. Once you find a face, make a new `VNTrackObjectRequest` for each face so that you can keep track of which face is which as they move around the camera.
   2. Use the `VNTrackObjectRequest` to track an object the user is interested in (like in this tutorial) then create a `VNCoreMLRequest` to use a machine learning model to attempt to identify what is in the boundingBox of the `VNDetectedObjectObservation`. Note that all 'VNRequest' objects and their subclasses have a `regionOfInterest` property. Set this to tell the handler which part of the `CVPixelBuffer` it should look at. This is how you can easy go from the `boundingBox` of an observation, to detecting what is inside that part of the image.


