`timescale 1ns / 1ps

// Main accelerator module for Convolutional Neural Network (CNN) operations
module accelerator #(
    parameter N = 16,     // 16-bit precision for activations and weights
                          // This provides a good balance between computational accuracy and hardware efficiency.
    parameter Q = 12,     // Number of fractional bits
                          // 12 bits for fractional values allow fine-grained precision, crucial for CNN calculations.
    parameter n = 6,      // Input image/activation map size (6x6)
                          // A smaller size chosen for demonstration, adjustable for larger input sizes.
    parameter k = 3,      // Convolution window size (3x3)
                          // This is a common filter size in CNNs, effective for feature extraction.
    parameter p = 2,      // Pooling window size (2x2)
                          // This size is standard, reducing the feature map size and computation cost.
    parameter s = 1,      // Stride during convolution
                          // A stride of 1 means the filter moves one step at a time, ensuring detailed feature extraction.
    parameter NUM_MAC = 4 // Number of parallel Multiply-Accumulate (MAC) units
                          // Four units increase throughput by allowing parallel operations.
)(
    input wire clk,       // Clock signal synchronizes all operations
    input wire rst,       // Reset signal initializes the system
    input wire en,        // Enable signal starts the processing
    input wire [N-1:0] activation_in, // Input activation map, provided one value at a time
    input wire [(k*k)*N-1:0] weight,  // All weights for convolution, provided together
    input wire [1:0] pool_type,       // Determines the type of pooling (00: max, 01: avg, 10: min)
    output wire [N-1:0] data_out,     // Final processed data output
    output wire valid_out,            // Indicates when the output data is valid
    output reg done                   // Signals completion of processing
);

    // Internal signals for connecting different processing stages
    wire [N-1:0] conv_out;  // Output from the convolution stage
    wire conv_valid, conv_done;  // Signals indicating valid convolution output and completion

    // Pipeline registers to store intermediate results and control signals
    reg [N-1:0] conv_out_reg;  // Register to store convolution output
    reg conv_valid_reg;        // Register to store validity of convolution output

    reg [N-1:0] quant_out_reg; // Register to store quantized output
    reg quant_valid_reg;       // Register to store validity of quantized output

    reg [N-1:0] relu_out_reg;  // Register to store ReLU output
    reg relu_valid_reg;        // Register to store validity of ReLU output

    // State machine for overall control, managing different stages of the pipeline
    reg [1:0] state;
    localparam IDLE = 2'b00,   // Idle state, waiting for enable signal
               CONV = 2'b01,   // Convolution state
               POOL = 2'b10,   // Pooling state
               FINISH = 2'b11; // Finish state, indicating completion

    // Convolution module instantiation
    // This module performs the core convolution operation using parallel MAC units
    convolver #(
        .N(N), .Q(Q), .n(n), .k(k), .s(s), .NUM_MAC(NUM_MAC)
    ) conv_inst (
        .clk(clk), .rst(rst), .en(en), .activation_in(activation_in),
        .weight(weight), .conv_out(conv_out),
        .valid_out(conv_valid), .done(conv_done)
    );

    // Quantization module instantiation
    // Reduces the precision of the data to save hardware resources and power
    wire [N-1:0] quant_out;
    quantizer #(.N(N), .Q(Q)) quant_inst (
        .din(conv_out_reg), .dout(quant_out)
    );

    // ReLU activation function module instantiation
    // Applies a non-linear transformation, critical for enabling the network to learn complex patterns
    wire [N-1:0] relu_out;
    relu #(.N(N)) relu_inst (
        .din_relu(quant_out_reg), .dout_relu(relu_out)
    );

    // Pooling module instantiation
    // Reduces the spatial dimensions of the output, making the representation more compact and computationally efficient
    wire pool_done;
    pooler #(
        .N(N), .m(n-k+1), .p(p)
    ) pool_inst (
        .clk(clk), .rst(rst), .en(relu_valid_reg),
        .data_in(relu_out_reg), .pool_type(pool_type),
        .data_out(data_out), .valid_out(valid_out),
        .done(pool_done)
    );

    // Pipeline register logic for maintaining data flow and synchronization
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // On reset, clear all pipeline registers
            conv_out_reg <= 0;
            conv_valid_reg <= 0;
            quant_out_reg <= 0;
            quant_valid_reg <= 0;
            relu_out_reg <= 0;
            relu_valid_reg <= 0;
        end else begin
            // Transfer data through the pipeline stages
            conv_out_reg <= conv_out;              // From convolution to quantization
            conv_valid_reg <= conv_valid;          // Validity signal for convolution output
            quant_out_reg <= quant_out;            // From quantization to ReLU
            quant_valid_reg <= conv_valid_reg;     // Validity signal for quantization output
            relu_out_reg <= relu_out;              // From ReLU to pooling
            relu_valid_reg <= quant_valid_reg;     // Validity signal for ReLU output
        end
    end

    // Control logic for managing the overall state of the accelerator
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;   // Set initial state to IDLE on reset
            done <= 0;       // Ensure 'done' signal is low at reset
        end else begin
            case (state)
                IDLE: begin
                    if (en) state <= CONV; // Start convolution when enabled
                    done <= 0;             // Ensure 'done' signal is reset
                end
                CONV: begin
                    if (conv_done) state <= POOL; // Transition to pooling after convolution is done
                end
                POOL: begin
                    if (pool_done) state <= FINISH; // Go to finish state after pooling
                end
                FINISH: begin
                    done <= 1;             // Indicate that processing is complete
                    state <= IDLE;         // Reset to IDLE state for next operation
                end
            endcase
        end
    end
endmodule
