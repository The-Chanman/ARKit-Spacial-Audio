/*
Copyright (C) 2017 Apple Inc. All Rights Reserved.
See LICENSE.txt for this sample’s licensing information

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, AVAudioPlayerDelegate {
	// MARK: - IBOutlets
	
	@IBOutlet weak var sessionInfoLabel: UILabel!
	@IBOutlet weak var sceneView: ARSCNView!
	
    var soundOfMusic: AVAudioPlayer?
    
	var screenCenter: CGPoint = .zero
	
	// Shows a preview of the object to be placed and hovers over estimated planes.
	var previewNode: PreviewNode?
	
	// Contains the cup model that is shared by the preview and final nodes.
	var objectNode = SCNNode()
	
	// Audio source for positional audio feedback.
	var source: SCNAudioSource?
	
	// MARK: - View Life Cycle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Show statistics such as FPS and timing information.
		sceneView.showsStatistics = true
		
		// Setup environment mapping.
		let environmentMap = UIImage(named: "Assets.scnassets/sharedImages/environment_blur.exr")!
		sceneView.scene.lightingEnvironment.contents = environmentMap
		
		// Complete rendering setup of ARSCNView.
		sceneView.antialiasingMode = .multisampling4X
		sceneView.automaticallyUpdatesLighting = false
		
		sceneView.contentScaleFactor = 1.3
		
		// Preload the audio file.
//        source = SCNAudioSource(fileNamed: "Assets.scnassets/Pure Imagination (Surface Studio cover).mp3")!
        source = SCNAudioSource(fileNamed: "Assets.scnassets/ping.aif")!
        source!.isPositional = true
        source!.shouldStream = false
		source!.loops = true
		source!.load()
        
        guard let fileURL = Bundle.main.url(forResource: "Assets.scnassets/3705", withExtension: ".mp3") else {
            print("could not read sound file")
            showUnsupportedMusicError()
            return
        }
        do {
            try soundOfMusic = AVAudioPlayer(contentsOf: fileURL)
            //try self.avPlayer = AVAudioPlayer(contentsOfURL: fileURL, fileTypeHint: AVFileTypeMPEGLayer3)
        } catch {
            print("could not create AVAudioPlayer \(error)")
            return
        }
        soundOfMusic?.prepareToPlay()
        soundOfMusic?.volume = 1.0
        soundOfMusic?.numberOfLoops = -1
        
	}
	
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard ARWorldTrackingConfiguration.isSupported
            else { showUnsupportedDeviceError(); return }

        // Start the ARSession.
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)

        screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)

        // Prevent the screen from being dimmed after a while as users will likely have
        // long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
    }
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		// Pause the view's session.
		sceneView.session.pause()
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		// The screen's center point changes on orientation switch, so recalculate `screenCenter`.
		screenCenter = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
	}
	
	// MARK: - Internal methods

    private func showUnsupportedDeviceError() {
        // This device does not support 6DOF world tracking.
        let alertController = UIAlertController(
            title: "ARKit is not available on this device.",
            message: "This app requires world tracking, which is available only on iOS devices with the A9 processor or later.",
            preferredStyle: .alert
        )

        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

        present(alertController, animated: true, completion: nil)
    }

    private func showUnsupportedMusicError() {
        // This device does not support 6DOF world tracking.
        let alertController = UIAlertController(
            title: "Can not find the correct music file.",
            message: "Please make sure that this app is loaded correctly.",
            preferredStyle: .alert
        )
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        present(alertController, animated: true, completion: nil)
    }
	// Check the light estimate from the current ARFrame and update the scene.
	private func updateLightEstimate() {
		if let lightEstimate = sceneView.session.currentFrame?.lightEstimate {
			sceneView.scene.lightingEnvironment.intensity = lightEstimate.ambientIntensity / 40.0
		} else {
			sceneView.scene.lightingEnvironment.intensity = 40.0
		}
	}
	
	private func resetTracking() {
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .horizontal
		sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
		// Reset preview state.
		objectNode.removeFromParentNode()
		objectNode = SCNNode()
		previewNode?.removeFromParentNode()
		previewNode = nil
		playSound()
	}
	
	private func setNewVirtualObjectToAnchor(_ object: SCNNode, to anchor: ARAnchor, cameraTransform: matrix_float4x4) {
		let cameraWorldPosition = cameraTransform.translation
		var cameraToPosition = anchor.transform.translation - cameraWorldPosition
		
		// Limit the distance of the object from the camera to a maximum of 10 meters.
		if simd_length(cameraToPosition) > 10 {
			cameraToPosition = simd_normalize(cameraToPosition)
			cameraToPosition *= 10
		}
		
		object.simdPosition = cameraWorldPosition + cameraToPosition
	}

	// MARK: - ARSCNViewDelegate
    /// - Tag: UpdateAudioPlayback
	func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
		if objectNode.parent == nil && previewNode == nil {
			// If our model hasn't been placed and we lack a preview for placement then setup a preview.
			setupPreviewNode()
			updatePreviewNode()
		} else {
			updatePreviewNode()
		}
		updateLightEstimate()
        cutVolumeIfFar()
//        print("Yo its the time Interval")
//        cutVolumeIfPlacedObjectIsInView()
	}
	
    /// - Tag: PlaceARContent
	func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {

        // Place content only for anchors found by plane detection.
        guard anchor is ARPlaneAnchor && previewNode != nil
            else { return }

        // Stop showing a preview version of the object to be placed.
        objectNode.removeFromParentNode()
		previewNode?.removeFromParentNode()
		previewNode = nil
		
		// Add the cupNode to the scene's root node using the anchor's position.
		guard let cameraTransform = sceneView.session.currentFrame?.camera.transform
            else { return }
		setNewVirtualObjectToAnchor(objectNode, to: anchor, cameraTransform: cameraTransform)
		sceneView.scene.rootNode.addChildNode(objectNode)
		
		// Disable plane detection after the model has been added.
		let configuration = ARWorldTrackingConfiguration()
		configuration.planeDetection = .horizontal
		sceneView.session.run(configuration, options: [])

        // Set up positional audio to play in case the object moves offscreen.
		playSound()
	}

	func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
		let message: String
		
		// Inform the user of their camera tracking state.
		switch camera.trackingState {
		case .notAvailable:
			message = "Tracking unavailable"
		case .normal:
			message = "Tracking normal"
		case .limited(.excessiveMotion):
			message = "Tracking limited - Too much camera movement"
		case .limited(.insufficientFeatures):
			message = "Tracking limited - Not enough surface detail"
		case .limited(.initializing):
			message = "Initializing AR Session"
		}
		
        sessionInfoLabel.text = message
	}
	
	func session(_ session: ARSession, didFailWithError error: Error) {
		// Present an error message to the user.
		sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
		resetTracking()
	}
	
	func sessionWasInterrupted(_ session: ARSession) {
		// Inform the user that the session has been interrupted, for example, by presenting an overlay.
		sessionInfoLabel.text = "Session was interrupted"
		resetTracking()
	}
	
	func sessionInterruptionEnded(_ session: ARSession) {
		// Reset tracking and/or remove existing anchors if consistent tracking is required.
		sessionInfoLabel.text = "Session interruption ended"
		resetTracking()
	}
	
	// MARK: - Preview Node
	
	/*
	Loads the cup model (`cupNode`) that is used for the duration of the app.
	Initializes a `PreviewNode` that contains the `cupNode` and adds it to the node hierarchy.
	*/
	func setupPreviewNode() {
		if (objectNode.childNode(withName: "cup", recursively: false) == nil) {
			// Load the cup scene from the bundle only once.
			let modelScene = SCNScene(named: "Assets.scnassets/Flair.dae")!
			// Get a handle to the cup model.
            let model_Eric_node = modelScene.rootNode.childNode(withName: "model_mesh", recursively: true)
            let Eric_Hips_node = modelScene.rootNode.childNode(withName: "mixamorig_Hips", recursively: true)
            
            let animationNode = SCNNode()
            animationNode.addChildNode(model_Eric_node!)
            animationNode.addChildNode(Eric_Hips_node!)
            animationNode.scale = SCNVector3Make(0.25, 0.25, 0.25)
//            let cup = modelScene.rootNode.childNode(withName: "model_mesh", recursively: true)!
			// Set the cup model onto `cupNode`.
			objectNode.addChildNode(animationNode)
		}
		// Initialize `previewNode` to display the cup model.
		previewNode = PreviewNode(node: objectNode)
		// Add `previewNode` to the node hierarchy.
		sceneView.scene.rootNode.addChildNode(previewNode!)
	}
	
	/*
	`previewNode` exists when ARKit is finding a plane. During this time, get a world position for the areas closest to the scene's point of view that ARKit believes might be a plane, and use it to update the `previewNode` position.
	*/
	func updatePreviewNode() {
		guard let node = previewNode else { return }
		let (worldPosition, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter,
		                                                                      in: sceneView,
		                                                                      objectPos: node.simdPosition)
		if let position = worldPosition {
			node.update(for: position, planeAnchor: planeAnchor, camera: sceneView.session.currentFrame?.camera)
		}
	}
	
	// MARK: - Sound
	
	/*
	Determines whether the `cupNode` is visible. If the `cupNode` isn't visible, a sound is played using
	SceneKit's positional audio functionality to locate the `cupNode`.
	*/
	func cutVolumeIfPlacedObjectIsInView() {
		guard previewNode == nil, let pointOfView = sceneView.pointOfView else { return }
		
		guard let player = objectNode.audioPlayers.first,
			let avNode = player.audioNode as? AVAudioMixing else {
				return
		}
		
		let placedObjectIsInView = sceneView.isNode(objectNode, insideFrustumOf: pointOfView)
		
		avNode.volume = placedObjectIsInView ? 0.0 : 1.0
	}
    
    /*
     Determines whether the `cupNode` is farther than 10 units away. If the `cupNode` is then cut the audio from the node.
     */
    func cutVolumeIfFar() {
//        guard let player = objectNode.audioPlayers.first,
//            let avNode = player.audioNode as? AVAudioMixing else {
//                return
//        }
        
        guard let cameraTransform = sceneView.session.currentFrame?.camera.transform
            else { return }
        let cameraWorldPosition = cameraTransform.translation
        let distanceToCamera = objectNode.simdPosition - cameraWorldPosition

        let bearingRadians = atan2f(distanceToCamera.y, distanceToCamera.x)
        var bearingDegrees = bearingRadians * (180.0 / .pi)
        while bearingDegrees < 0 {
            bearingDegrees += 360
        }
        let frame = self.sceneView.session.currentFrame
        let mat = SCNMatrix4((frame?.camera.transform)!) // 4x4 transform matrix describing camera in world space
        let dir = SCNVector3(-1 * mat.m31, -1 * mat.m32, -1 * mat.m33)
        var cameraAngle = atan2f(dir.z, dir.x) * (180.0 / .pi)
        while cameraAngle < 0 {
            cameraAngle += 360
        }
        
        print("Angle of Direction: " + String(bearingDegrees) + "Angle of Camera: " + String(cameraAngle))
        
        var relativeAngle = cameraAngle - bearingDegrees
        while relativeAngle < 0 {
            relativeAngle += 360
        }
        print(relativeAngle)
        if relativeAngle < 90 {
            soundOfMusic?.pan = remap(value: relativeAngle, from1: 0, to1: 90, from2: 0, to2: -1)
        } else if relativeAngle < 180 {
            soundOfMusic?.pan = remap(value: relativeAngle, from1: 90, to1: 180, from2: -1, to2: 0)
        } else if relativeAngle < 270 {
            soundOfMusic?.pan = remap(value: relativeAngle, from1: 180, to1: 270, from2: 0, to2: 1)
        } else if relativeAngle <= 360 {
            soundOfMusic?.pan = remap(value: relativeAngle, from1: 270, to1: 360, from2: 1, to2: 0)
        }

        
        let maxDistance = 6
        if simd_length(distanceToCamera) > Float(maxDistance) {
//            avNode.volume = 0.0
//            soundOfMusic?.setVolume(0.0, fadeDuration: 0.2)
            soundOfMusic?.volume = 0.0
        } else {
            let mappedVolume = 1.0 - ((simd_length(distanceToCamera) - 0.0)/Float(maxDistance) - 0.0) * 1.0
//            let mappedLogVolume = (1.0 * log(simd_length(distanceToCamera)))
//            avNode.volume = mappedVolume
//            avNode.volume = 1.0
//            soundOfMusic?.setVolume(mappedVolume, fadeDuration: 0.2)
            soundOfMusic?.volume = mappedVolume
            
//            sessionInfoLabel.text = String(mappedVolume)
            print(String(mappedVolume))
        }
    }
	
	// Plays a sound on the cupNode using SceneKit's positional audio.
    /// - Tag: AddAudioPlayer
	func playSound() {
//        guard cupNode.audioPlayers.count == 0 else { return }
//        cupNode.addAudioPlayer(SCNAudioPlayer(source: source!))
        soundOfMusic?.play()
	}
    func remap(value: Float,from1: Float,to1: Float,from2: Float ,to2: Float) -> Float{
        let a = (value - from1)
        let b = (to1 - from1)
        let c = (to2 - from2)
        return (a) / (b) * (c) + from2
    }
}
