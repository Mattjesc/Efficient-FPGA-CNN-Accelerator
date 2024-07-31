`timescale 1ns / 1ps

// Quantizer module for reducing the precision of data
module quantizer #(
    parameter N = 16,     // Bit width of input/output data, balancing detail and hardware efficiency
    parameter Q = 12      // Number of fractional bits to retain, providing fine-grained control over precision
)(
    input [N-1:0] din,    // Input data, represented as a signed fixed-point number
    output [N-1:0] dout   // Quantized output data with reduced precision
);

    // Perform quantization by truncating the least significant bits
    // The operation discards lower precision bits, effectively reducing the data's resolution
    assign dout = {din[N-1], din[N-2:Q-1], {(Q-1){1'b0}}};

    // Detailed explanation of the quantization process:
    // 1. **Keep the Sign Bit (din[N-1])**: This bit indicates whether the number is positive or negative.
    // 2. **Retain Most Significant Bits (din[N-2:Q-1])**: These bits represent the integer and high-precision fractional part. 
    //    By keeping these bits, we maintain the significant portion of the data.
    // 3. **Set Remaining Bits to Zero ({(Q-1){1'b0}})**: The least significant bits are set to zero, removing finer details. 
    //    This simplification reduces the data's precision, but it also reduces the amount of hardware needed for storage and computation.

    // The result is a fixed-point number with fewer fractional bits, reducing both computational complexity and memory usage. 
    // This is particularly useful in hardware implementations where resource constraints are critical.

    // Note: This form of quantization does not include any rounding. It simply truncates the fractional part, 
    // which might introduce a slight bias towards zero. For applications requiring more precision, additional rounding logic can be implemented.

endmodule
