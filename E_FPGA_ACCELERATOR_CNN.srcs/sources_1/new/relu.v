`timescale 1ns / 1ps

// ReLU (Rectified Linear Unit) activation function module
module relu #(parameter N = 16)( // N is the bit width of input/output
    input [N-1:0] din_relu,     // Input data to ReLU function
    output [N-1:0] dout_relu    // Output data after ReLU activation
);
    // Efficient ReLU implementation using a ternary operator
    // If the input is negative (MSB is 1), output 0; otherwise, pass the input unchanged
    assign dout_relu = din_relu[N-1] ? {N{1'b0}} : din_relu;
    
    // This implementation is area-efficient and introduces minimal delay
    // It effectively creates a non-linear activation function crucial for neural network operations
endmodule
