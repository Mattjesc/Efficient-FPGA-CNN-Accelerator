`timescale 1ns / 1ps

// Main accelerator module for Convolutional Neural Network (CNN) operations
module accelerator #(
    parameter N = 16,     // Bit width of activations and weights (16-bit precision for balance between accuracy and hardware efficiency)
    parameter Q = 12,     // Number of fractional bits (12 bits allow for fine-grained representation of fractional values)
    parameter n = 6,      // Size of the input image/activation map (6x6 for demonstration, can be adjusted for larger inputs)
    parameter k = 3,      // Size of the convolution window (3x3 is a common filter size in CNNs)
    parameter p = 2,      // Size of the pooling window (2x2 is standard for reducing spatial dimensions)
    parameter s = 1,      // Stride value during convolution (1 for this example, can be increased for faster but less detailed convolution)
    parameter NUM_MAC = 4 // Number of parallel MAC units (4 for increased parallelism and throughput)
)(
    input wire clk,            // Clock signal for synchronizing operations
    input wire rst,            // Reset signal for initializing the module
    input wire en,             // Enable signal to start processing
    input wire [N-1:0] activation_in, // Input activation map (streamed in one value at a time)
    input wire [(k*k)*N-1:0] weight, // Input weights for convolution (all weights loaded at once)
    input wire [1:0] pool_type,  // Selects pooling type: 00: max, 01: avg, 10: min
    output wire [N-1:0] data_out, // Final output data after all processing stages
    output wire valid_out,     // Indicates when the output data is valid
    output reg done           // Signals the completion of all operations
);
    // Internal signals for connecting different stages
    wire [N-1:0] conv_out;
    wire conv_valid, conv_done;
    
    // Pipeline registers to store intermediate results and control signals
    reg [N-1:0] conv_out_reg;
    reg conv_valid_reg;
    
    reg [N-1:0] quant_out_reg;
    reg quant_valid_reg;
    
    reg [N-1:0] relu_out_reg;
    reg relu_valid_reg;

    // State machine for overall control of the accelerator
    reg [1:0] state;
    localparam IDLE = 2'b00, CONV = 2'b01, POOL = 2'b10, FINISH = 2'b11;

    // Instantiate the enhanced convolver module
    convolver #(
        .N(N), .Q(Q), .n(n), .k(k), .s(s), .NUM_MAC(NUM_MAC)
    ) conv_inst (
        .clk(clk),
        .rst(rst),
        .en(en),
        .activation_in(activation_in),
        .weight(weight),
        .conv_out(conv_out),
        .valid_out(conv_valid),
        .done(conv_done)
    );

    // Instantiate the quantization module to reduce precision and save resources
    wire [N-1:0] quant_out;
    quantizer #(.N(N), .Q(Q)) quant_inst (
        .din(conv_out_reg),
        .dout(quant_out)
    );

    // Instantiate the enhanced ReLU activation module for non-linearity
    wire [N-1:0] relu_out;
    relu #(.N(N)) relu_inst (
        .din_relu(quant_out_reg),
        .dout_relu(relu_out)
    );

    // Instantiate the enhanced pooling module for spatial dimension reduction
    wire pool_done;
    pooler #(
        .N(N), .m(n-k+1), .p(p)
    ) pool_inst (
        .clk(clk),
        .rst(rst),
        .en(relu_valid_reg),
        .data_in(relu_out_reg),
        .pool_type(pool_type),
        .data_out(data_out),
        .valid_out(valid_out),
        .done(pool_done)
    );

    // Pipeline register logic to ensure proper data flow and timing
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all pipeline registers
            conv_out_reg <= 0;
            conv_valid_reg <= 0;
            quant_out_reg <= 0;
            quant_valid_reg <= 0;
            relu_out_reg <= 0;
            relu_valid_reg <= 0;
        end else begin
            // Convolution to Quantization pipeline
            conv_out_reg <= conv_out;
            conv_valid_reg <= conv_valid;
            
            // Quantization to ReLU pipeline
            quant_out_reg <= quant_out;
            quant_valid_reg <= conv_valid_reg;
            
            // ReLU to Pooling pipeline
            relu_out_reg <= relu_out;
            relu_valid_reg <= quant_valid_reg;
        end
    end

    // Overall control logic for managing the accelerator's state
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (en) state <= CONV; // Start convolution when enabled
                    done <= 0;
                end
                CONV: begin
                    if (conv_done) state <= POOL; // Move to pooling after convolution
                end
                POOL: begin
                    if (pool_done) state <= FINISH; // Finish after pooling
                end
                FINISH: begin
                    done <= 1; // Signal completion
                    state <= IDLE; // Return to idle state
                end
            endcase
        end
    end
endmodule