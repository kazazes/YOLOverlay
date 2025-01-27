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
    
    // Find maximum probability and compute softmax
    float maxProb = -INFINITY;
    float sum = 0.0;
    float probs[32];  // Assuming max 32 classes
    
    // First pass - find max and compute exponentials
    for (uint c = 0; c < numClasses; c++) {
        uint idx = (c * height + y) * width + gid.x;
        float prob = maskData[idx];
        maxProb = max(maxProb, prob);
        probs[c] = prob;
    }
    
    // Second pass - compute softmax probabilities
    uint maxClass = 0;
    float maxSoftmaxProb = 0.0;
    
    for (uint c = 0; c < numClasses; c++) {
        float expVal = exp(probs[c] - maxProb);  // Subtract max for numerical stability
        sum += expVal;
        probs[c] = expVal;
    }
    
    // Find class with maximum softmax probability
    for (uint c = 0; c < numClasses; c++) {
        float softmaxProb = probs[c] / sum;
        if (softmaxProb > maxSoftmaxProb) {
            maxSoftmaxProb = softmaxProb;
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
    float alpha = maxSoftmaxProb > threshold ? opacity : 0.0;
    
    // Write output
    output.write(float4(color, alpha), gid);
} 