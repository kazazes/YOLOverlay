#include <metal_stdlib>
using namespace metal;

kernel void segmentationKernel(
    device const float* maskData [[buffer(0)]],
    device const float* colorData [[buffer(1)]],
    texture2d<float, access::write> output [[texture(0)]],
    constant uint& width [[buffer(2)]],
    constant uint& height [[buffer(3)]],
    constant uint& numClasses [[buffer(4)]],
    constant float& opacity [[buffer(5)]],
    constant float& threshold [[buffer(6)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Check bounds
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Flip Y coordinate
    uint y = height - 1 - gid.y;
    
    // Find class with maximum probability
    float maxProb = 0.0;
    uint maxClass = 0;
    
    // In NCHW format, for each pixel (h,w), the class probabilities start at:
    // batch=0, class=c, height=h, width=w
    // Index = ((0 * numClasses + c) * height + h) * width + w
    for (uint c = 0; c < numClasses; c++) {
        uint idx = (c * height + y) * width + gid.x;
        float prob = maskData[idx];
        if (prob > maxProb) {
            maxProb = prob;
            maxClass = c;
        }
    }
    
    // Get color for max class
    float3 color = float3(
        colorData[maxClass * 3],
        colorData[maxClass * 3 + 1],
        colorData[maxClass * 3 + 2]
    );
    
    // Apply threshold and opacity
    float alpha = maxProb > threshold ? opacity * maxProb : 0.0;
    
    // Write output
    output.write(float4(color, alpha), gid);
} 