import CoreML
import Foundation
import MetalKit
import SwiftUI

class SegmentationRenderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLComputePipelineState
  private let ciContext: CIContext

  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
      let commandQueue = device.makeCommandQueue()
    else {
      return nil
    }

    self.device = device
    self.commandQueue = commandQueue
    self.ciContext = CIContext(mtlDevice: device)

    // Create compute pipeline for mask rendering
    guard let library = device.makeDefaultLibrary(),
          let kernelFunction = library.makeFunction(name: "segmentationKernel")
    else {
      return nil
    }

    do {
      self.pipelineState = try device.makeComputePipelineState(function: kernelFunction)
    } catch {
      LogManager.shared.error("Failed to create pipeline state", error: error)
      return nil
    }
  }

  func renderMask(
    mask: MLMultiArray,
    classColors: [String: String],
    classLabels: [String],
    opacity: Float
  ) -> CGImage? {
    LogManager.shared.info("=== Starting Segmentation Rendering Pipeline ===")
    
    // Log input dimensions
    LogManager.shared.info("Input mask dimensions:")
    LogManager.shared.info("- Raw shape: \(mask.shape)")
    LogManager.shared.info("- Strides: \(mask.strides)")
    LogManager.shared.info("- Data type: \(mask.dataType)")
    
    // Parse dimensions from mask shape
    let width = mask.shape[3].intValue  // Last dimension is width
    let height = mask.shape[2].intValue  // Second to last is height
    let numClasses = mask.shape[1].intValue  // Second dimension is number of classes
    let totalElements = width * height * numClasses
    
    LogManager.shared.info("Parsed dimensions:")
    LogManager.shared.info("- Width: \(width)")
    LogManager.shared.info("- Height: \(height)")
    LogManager.shared.info("- Number of classes: \(numClasses)")
    LogManager.shared.info("- Total elements: \(totalElements)")
    
    // Create color data array
    var colorData = [Float]()
    LogManager.shared.info("\nProcessing colors for \(classLabels.count) classes:")
    for label in classLabels {
      let hexColor = classColors[label] ?? "#FF0000"
      
      // Parse hex color
      var r: Float = 0.0
      var g: Float = 0.0
      var b: Float = 0.0
      
      let hex = hexColor.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      if hex.count == 6 {
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        
        if scanner.scanHexInt64(&hexNumber) {
          r = Float((hexNumber & 0xFF0000) >> 16) / 255.0
          g = Float((hexNumber & 0x00FF00) >> 8) / 255.0
          b = Float(hexNumber & 0x0000FF) / 255.0
          LogManager.shared.info("- \(label): \(hexColor) -> RGB(\(r), \(g), \(b))")
        }
      }
      
      colorData.append(contentsOf: [r, g, b])
    }
    
    // Log buffer sizes
    LogManager.shared.info("\nBuffer sizes:")
    let colorBufferSize = colorData.count * MemoryLayout<Float>.stride
    let maskBufferSize = height * width * numClasses * MemoryLayout<Float>.stride
    LogManager.shared.info("- Color buffer: \(colorBufferSize) bytes")
    LogManager.shared.info("- Mask buffer: \(maskBufferSize) bytes")
    
    // Create buffers
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let colorBuffer = device.makeBuffer(bytes: colorData,
                                           length: colorBufferSize,
                                           options: []),
          let maskBuffer = device.makeBuffer(bytes: mask.dataPointer,
                                          length: maskBufferSize,
                                          options: []) else {
      LogManager.shared.error("Failed to create Metal buffers")
      return nil
    }
    
    // Create output texture with correct dimensions
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    textureDescriptor.usage = [.shaderRead, .shaderWrite]
    
    guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
      LogManager.shared.error("Failed to create output texture")
      return nil
    }
    
    LogManager.shared.info("\nOutput texture configuration:")
    LogManager.shared.info("- Width: \(outputTexture.width)")
    LogManager.shared.info("- Height: \(outputTexture.height)")
    LogManager.shared.info("- Pixel format: \(outputTexture.pixelFormat.rawValue)")
    
    // Create command encoder
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
      LogManager.shared.error("Failed to create compute encoder")
      return nil
    }
    
    // Convert dimensions to UInt32 for Metal
    var widthMetal: UInt32 = UInt32(width)
    var heightMetal: UInt32 = UInt32(height)
    var numClassesMetal: UInt32 = UInt32(numClasses)
    var opacityMetal: Float = opacity
    
    LogManager.shared.info("\nMetal parameters:")
    LogManager.shared.info("- Width: \(widthMetal)")
    LogManager.shared.info("- Height: \(heightMetal)")
    LogManager.shared.info("- Classes: \(numClassesMetal)")
    LogManager.shared.info("- Opacity: \(opacityMetal)")
    
    computeEncoder.setComputePipelineState(pipelineState)
    computeEncoder.setBuffer(maskBuffer, offset: 0, index: 0)
    computeEncoder.setBuffer(colorBuffer, offset: 0, index: 1)
    computeEncoder.setTexture(outputTexture, index: 0)
    computeEncoder.setBytes(&widthMetal, length: MemoryLayout<UInt32>.size, index: 2)
    computeEncoder.setBytes(&heightMetal, length: MemoryLayout<UInt32>.size, index: 3)
    computeEncoder.setBytes(&numClassesMetal, length: MemoryLayout<UInt32>.size, index: 4)
    computeEncoder.setBytes(&opacityMetal, length: MemoryLayout<Float>.size, index: 5)
    
    // Calculate thread groups based on actual dimensions
    let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
    let threadGroups = MTLSize(
        width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
        height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
        depth: 1
    )
    
    LogManager.shared.info("\nThread configuration:")
    LogManager.shared.info("- Thread group size: \(threadGroupSize.width)x\(threadGroupSize.height)")
    LogManager.shared.info("- Thread groups: \(threadGroups.width)x\(threadGroups.height)")
    
    computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
    computeEncoder.endEncoding()
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    // Create CIImage from texture
    guard let ciImage = CIImage(mtlTexture: outputTexture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else {
      LogManager.shared.error("Failed to create CIImage from texture")
      return nil
    }
    
    LogManager.shared.info("\nCIImage properties:")
    LogManager.shared.info("- Extent: \(ciImage.extent)")
    LogManager.shared.info("- Properties: \(ciImage.properties)")
    
    // Create CGImage with original dimensions
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    guard let cgImage = ciContext.createCGImage(ciImage, from: bounds) else {
      LogManager.shared.error("Failed to create CGImage from CIImage")
      return nil
    }
    
    LogManager.shared.info("\nFinal CGImage properties:")
    LogManager.shared.info("- Width: \(cgImage.width)")
    LogManager.shared.info("- Height: \(cgImage.height)")
    LogManager.shared.info("- Scale: \(cgImage.width)/\(width)x\(cgImage.height)/\(height)")
    LogManager.shared.info("- Bits per component: \(cgImage.bitsPerComponent)")
    LogManager.shared.info("- Bytes per row: \(cgImage.bytesPerRow)")
    LogManager.shared.info("=== Segmentation Rendering Pipeline Complete ===\n")
    
    return cgImage
  }
}
