`timescale 1ns / 1ps

// Quantizer module for reducing precision of data
module quantizer #(
    parameter N = 16,     // Bit width of input/output
    parameter Q = 12      // Number of fractional bits to retain
)(
    input [N-1:0] din,    // Input data
    output [N-1:0] dout   // Quantized output data
);

    // Perform quantization by truncating least significant bits
    // This operation effectively rounds towards zero
    assign dout = {din[N-1], din[N-2:Q-1], {(Q-1){1'b0}}};

    // Explanation of the quantization process:
    // 1. Keep the sign bit (din[N-1])
    // 2. Retain the most significant bits up to the desired fractional precision (din[N-2:Q-1])
    // 3. Set the remaining least significant bits to zero ({(Q-1){1'b0}})
    
    // This quantization method reduces the precision of the fractional part
    // while maintaining the overall range of representable values.
    // It's a simple form of fixed-point quantization commonly used in hardware implementations
    // to reduce computational complexity and memory requirements.

    // Note: This method does not perform any rounding, which might lead to a slight bias towards zero.
    // For more accurate results, consider implementing proper rounding techniques.

endmodule