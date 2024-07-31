`timescale 1ns / 1ps

// Convolver module: Performs the convolution operation for a CNN layer
module convolver #(
    parameter N = 16,     // Bit width of activations and weights (16-bit for balance between precision and hardware cost)
    parameter Q = 12,     // Number of fractional bits (12 bits allow for fine-grained representation of fractional values)
    parameter n = 6,      // Size of the input image/activation map (6x6 for demonstration, adjustable for different input sizes)
    parameter k = 3,      // Size of the convolution window (3x3 is a common filter size in CNNs)
    parameter s = 1,      // Stride value during convolution (1 for full detail, can be increased for faster but less detailed convolution)
    parameter NUM_MAC = 4 // Number of parallel MAC units (4 for increased parallelism and throughput)
)(
    input wire clk,                   // Clock signal for synchronizing operations
    input wire rst,                   // Reset signal for initializing the module
    input wire en,                    // Enable signal to start processing
    input wire [N-1:0] activation_in, // Input activation map (streamed in one value at a time)
    input wire [(k*k*N)-1:0] weight,  // Input weights for convolution (all weights loaded at once)
    output reg [N-1:0] conv_out,      // Output of the convolution operation
    output reg valid_out,             // Indicates when the output data is valid
    output reg done                   // Signals the completion of the convolution operation
);
    // Line buffer: Stores (k-1) rows of the input for efficient sliding window operation
    reg [N-1:0] line_buffer [(k-1)*n-1:0];
    
    // Window buffer: Represents the current k x k window for convolution
    wire [N-1:0] window_buffer [k*k-1:0];
    
    // Counters and control signals
    reg [$clog2(n*n)-1:0] input_counter;        // Counts input activations
    reg [$clog2((n-k+1)*(n-k+1))-1:0] output_counter; // Counts output results
    reg [$clog2(k)-1:0] row_counter;            // Tracks current row in the sliding window
    
    // State machine for controlling the convolution process
    localparam IDLE = 2'b00, LOAD = 2'b01, COMPUTE = 2'b10, DONE = 2'b11;
    reg [1:0] state, next_state;

    integer i; // Loop variable

    // Line buffer shift register logic
    always @(posedge clk) begin
        if (rst) begin
            // Reset line buffer to zero
            for (i = 0; i < (k-1)*n; i = i + 1) begin
                line_buffer[i] <= 0;
            end
        end else if (en && state == LOAD) begin
            // Shift data in the line buffer
            for (i = (k-1)*n-1; i > 0; i = i - 1) begin
                line_buffer[i] <= line_buffer[i-1];
            end
            line_buffer[0] <= activation_in; // Input new activation
        end
    end

    // Window buffer assignment: Creates the sliding window from line buffer
    genvar x, y;
    generate
        for (y = 0; y < k; y = y + 1) begin : window_row
            for (x = 0; x < k; x = x + 1) begin : window_col
                if (y == k-1) begin
                    // Bottom row of window comes directly from input
                    assign window_buffer[y*k + x] = line_buffer[x];
                end else begin
                    // Other rows come from line buffer
                    assign window_buffer[y*k + x] = line_buffer[y*n + x];
                end
            end
        end
    endgenerate

    // Convolution computation: Multiply-accumulate operations
    reg [N-1:0] conv_temp;
    always @(*) begin
        conv_temp = 0;
        for (i = 0; i < k*k; i = i + 1) begin
            // Multiply each window element with corresponding weight and accumulate
            conv_temp = conv_temp + (($signed(window_buffer[i]) * $signed(weight[i*N +: N])) >>> Q);
        end
    end

    // State machine and control logic
    always @(posedge clk) begin
        if (rst) begin
            // Reset all counters and control signals
            state <= IDLE;
            input_counter <= 0;
            output_counter <= 0;
            row_counter <= 0;
            valid_out <= 0;
            done <= 0;
            conv_out <= 0;
        end else if (en) begin
            state <= next_state;
            case (state)
                LOAD: begin
                    input_counter <= input_counter + 1;
                    if (input_counter % n == n-1) row_counter <= row_counter + 1;
                    valid_out <= 0;
                end
                COMPUTE: begin
                    if (row_counter >= k-1) begin
                        conv_out <= conv_temp;
                        valid_out <= 1;
                        output_counter <= output_counter + 1;
                    end
                end
                DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        case (state)
            IDLE: next_state = en ? LOAD : IDLE;
            LOAD: next_state = (input_counter == n*n - 1) ? COMPUTE : 
                               (input_counter >= (k-1)*n && (input_counter+1) % s == 0) ? COMPUTE : LOAD;
            COMPUTE: next_state = (output_counter == (n-k+1)*(n-k+1) - 1) ? DONE : 
                                  (((output_counter+1) % (n-k+1) == 0) || (output_counter == 0)) ? LOAD : COMPUTE;
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Logging for debugging and verification (can be removed in final implementation)
    always @(posedge clk) begin
        if (en) begin
            $display("Time %t: State = %s, Next State = %s", $time, state_to_string(state), state_to_string(next_state));
            $display("input_counter = %d, output_counter = %d, row_counter = %d", input_counter, output_counter, row_counter);
            
            if (state == COMPUTE) begin
                $display("Convolution Result: conv_temp = %h", conv_temp);
                for (i = 0; i < k*k; i = i + 1) begin
                    $display("window_buffer[%d] = %h, weight[%d] = %h, product = %h", 
                             i, window_buffer[i], i, weight[i*N +: N], 
                             ($signed(window_buffer[i]) * $signed(weight[i*N +: N])) >>> Q);
                end
            end
            
            if (valid_out) begin
                $display("Valid Output: conv_out = %h", conv_out);
            end
            
            if (done) begin
                $display("Convolution operation completed");
            end
        end
    end

    // Helper function to convert state to string for logging
    function automatic [23:0] state_to_string(input [1:0] state);
        case (state)
            IDLE: state_to_string = "IDLE";
            LOAD: state_to_string = "LOAD";
            COMPUTE: state_to_string = "COMPUTE";
            DONE: state_to_string = "DONE";
            default: state_to_string = "UNKNOWN";
        endcase
    endfunction

endmodule