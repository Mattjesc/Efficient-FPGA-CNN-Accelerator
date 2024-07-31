`timescale 1ns / 1ps

// Convolver module: Performs the convolution operation for a CNN layer
module convolver #(
    parameter N = 16,     // Bit width for data precision, chosen to balance detail and hardware efficiency
    parameter Q = 12,     // Number of bits used for fractional values, allowing precise fractional computations
    parameter n = 6,      // Dimension of the input image, set to 6x6 for demonstration purposes
    parameter k = 3,      // Size of the convolution filter, 3x3 is typical for detecting small features
    parameter s = 1,      // Stride for convolution, a value of 1 means the filter moves one step at a time
    parameter NUM_MAC = 4 // Number of Multiply-Accumulate (MAC) units working in parallel for faster processing
)(
    input wire clk,                   // Clock signal that synchronizes all operations
    input wire rst,                   // Reset signal to initialize the system to a known state
    input wire en,                    // Enable signal that triggers the start of the operation
    input wire [N-1:0] activation_in, // Incoming data (activations), provided sequentially
    input wire [(k*k*N)-1:0] weight,  // All weights for the convolution, provided at once
    output reg [N-1:0] conv_out,      // Result of the convolution operation
    output reg valid_out,             // Signal indicating the convolution result is ready to use
    output reg done                   // Signal indicating the convolution operation is complete
);

    // Line buffer stores several rows of the input image to facilitate the sliding window mechanism
    reg [N-1:0] line_buffer [(k-1)*n-1:0];

    // Window buffer represents the current k x k window used for the convolution operation
    wire [N-1:0] window_buffer [k*k-1:0];

    // Various counters and control signals
    reg [$clog2(n*n)-1:0] input_counter;        // Tracks the number of input elements processed
    reg [$clog2((n-k+1)*(n-k+1))-1:0] output_counter; // Tracks the number of outputs generated
    reg [$clog2(k)-1:0] row_counter;            // Keeps track of rows during the sliding window movement

    // State machine to control the convolution process
    localparam IDLE = 2'b00, LOAD = 2'b01, COMPUTE = 2'b10, DONE = 2'b11;
    reg [1:0] state, next_state; // Current and next state variables

    integer i; // Loop variable used in procedural blocks

    // Line buffer shift register logic: Shifts input data through the buffer
    always @(posedge clk) begin
        if (rst) begin
            // On reset, initialize all buffer entries to zero
            for (i = 0; i < (k-1)*n; i = i + 1) begin
                line_buffer[i] <= 0;
            end
        end else if (en && state == LOAD) begin
            // Shift existing data to make room for new incoming data
            for (i = (k-1)*n-1; i > 0; i = i - 1) begin
                line_buffer[i] <= line_buffer[i-1];
            end
            line_buffer[0] <= activation_in; // Place new data in the buffer
        end
    end

    // Window buffer assignment: Collects data from the line buffer to form the k x k window
    genvar x, y;
    generate
        for (y = 0; y < k; y = y + 1) begin : window_row
            for (x = 0; x < k; x = x + 1) begin : window_col
                if (y == k-1) begin
                    // The bottom row of the window is populated directly from new data
                    assign window_buffer[y*k + x] = line_buffer[x];
                end else begin
                    // The rest of the window is populated from the line buffer
                    assign window_buffer[y*k + x] = line_buffer[y*n + x];
                end
            end
        end
    endgenerate

    // Convolution computation: Computes the sum of products for the k x k window and weights
    reg [N-1:0] conv_temp;
    always @(*) begin
        conv_temp = 0;
        for (i = 0; i < k*k; i = i + 1) begin
            // Multiply each window element with the corresponding weight, and accumulate the result
            conv_temp = conv_temp + (($signed(window_buffer[i]) * $signed(weight[i*N +: N])) >>> Q);
        end
    end

    // State machine and control logic: Manages the convolution process
    always @(posedge clk) begin
        if (rst) begin
            // On reset, initialize all state variables and counters
            state <= IDLE;
            input_counter <= 0;
            output_counter <= 0;
            row_counter <= 0;
            valid_out <= 0;
            done <= 0;
            conv_out <= 0;
        end else if (en) begin
            state <= next_state; // Move to the next state as determined by the next state logic
            case (state)
                LOAD: begin
                    // Increment counters as input data is loaded
                    input_counter <= input_counter + 1;
                    if (input_counter % n == n-1) row_counter <= row_counter + 1;
                    valid_out <= 0; // Output is not valid yet
                end
                COMPUTE: begin
                    if (row_counter >= k-1) begin
                        // Once the window is ready, perform convolution and set output as valid
                        conv_out <= conv_temp;
                        valid_out <= 1;
                        output_counter <= output_counter + 1;
                    end
                end
                DONE: begin
                    // Set the done signal to indicate the completion of the convolution process
                    done <= 1;
                end
            endcase
        end
    end

    // Logic to determine the next state in the state machine
    always @(*) begin
        case (state)
            IDLE: next_state = en ? LOAD : IDLE; // Start loading data if enabled
            LOAD: next_state = (input_counter == n*n - 1) ? COMPUTE : 
                               (input_counter >= (k-1)*n && (input_counter+1) % s == 0) ? COMPUTE : LOAD;
                               // Move to COMPUTE when enough data is loaded, considering stride
            COMPUTE: next_state = (output_counter == (n-k+1)*(n-k+1) - 1) ? DONE : 
                                  (((output_counter+1) % (n-k+1) == 0) || (output_counter == 0)) ? LOAD : COMPUTE;
                                  // Return to LOAD for the next row, or finish if all outputs are computed
            DONE: next_state = IDLE; // Return to IDLE after finishing computation
            default: next_state = IDLE;
        endcase
    end

    // Logging for debugging and verification (useful during development and testing)
    always @(posedge clk) begin
        if (en) begin
            // Print current state and relevant information for debugging
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

    // Helper function to convert state to string for logging purposes
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
