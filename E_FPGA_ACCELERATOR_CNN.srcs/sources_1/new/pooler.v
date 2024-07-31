`timescale 1ns / 1ps

// Pooler module: Performs the pooling operation in a CNN layer
module pooler #(
    parameter N = 16,     // Bit width for data precision, balancing detail and hardware efficiency
    parameter m = 4,      // Size of the input feature map, here set to 4x4 for demonstration purposes
    parameter p = 2       // Size of the pooling window, 2x2 is standard for reducing data size
)(
    input wire clk,              // Clock signal for synchronizing all operations
    input wire rst,              // Reset signal to initialize the system to a known state
    input wire en,               // Enable signal to start processing data
    input wire [N-1:0] data_in,  // Incoming data stream to be pooled
    input wire [1:0] pool_type,  // Selects the pooling operation: 00: max, 01: avg, 10: min
    output reg [N-1:0] data_out, // Output data after pooling operation
    output reg valid_out,        // Indicates when the output data is valid and can be used
    output reg done              // Signals that all pooling operations are complete
);

    // Pooling window buffer: Temporarily stores p*p elements for processing
    reg [N-1:0] pool_buffer [p*p-1:0];

    // Counters for tracking the number of processed inputs and outputs
    reg [$clog2(m*m)-1:0] input_counter;     // Counts the number of input elements processed
    reg [$clog2((m/p)*(m/p))-1:0] output_counter; // Counts the number of output elements generated

    // State machine for controlling the pooling process
    localparam IDLE = 2'b00, LOAD = 2'b01, COMPUTE = 2'b10, DONE = 2'b11;
    reg [1:0] state, next_state; // Current and next state variables

    integer i; // Loop variable used for iterating through the pool buffer

    // Pooling computation logic: Determines the result based on the pooling type
    reg [N-1:0] pool_result;
    always @(*) begin
        case (pool_type)
            2'b00: begin // Max pooling: Selects the maximum value in the pooling window
                pool_result = pool_buffer[0];
                for (i = 1; i < p*p; i = i + 1) begin
                    if ($signed(pool_buffer[i]) > $signed(pool_result))
                        pool_result = pool_buffer[i];
                end
            end
            2'b01: begin // Average pooling: Calculates the average of values in the pooling window
                pool_result = 0;
                for (i = 0; i < p*p; i = i + 1) begin
                    pool_result = pool_result + pool_buffer[i];
                end
                pool_result = pool_result / (p*p); // Divide by the number of elements
            end
            2'b10: begin // Min pooling: Selects the minimum value in the pooling window
                pool_result = pool_buffer[0];
                for (i = 1; i < p*p; i = i + 1) begin
                    if ($signed(pool_buffer[i]) < $signed(pool_result))
                        pool_result = pool_buffer[i];
                end
            end
            default: pool_result = pool_buffer[0]; // Fallback in case of an undefined operation
        endcase
    end

    // State machine and control logic: Manages the pooling operation process
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // On reset, initialize all state variables, counters, and buffers
            state <= IDLE;
            input_counter <= 0;
            output_counter <= 0;
            valid_out <= 0;
            done <= 0;
            data_out <= 0;
            for (i = 0; i < p*p; i = i + 1) begin
                pool_buffer[i] <= 0;
            end
        end else begin
            state <= next_state; // Transition to the next state
            case (state)
                IDLE: begin
                    if (en) begin
                        // Initialize counters and flags when pooling is enabled
                        input_counter <= 0;
                        output_counter <= 0;
                        valid_out <= 0;
                        done <= 0;
                    end
                end
                LOAD: begin
                    if (en) begin
                        // Load input data into the pool buffer
                        pool_buffer[input_counter] <= data_in;
                        input_counter <= input_counter + 1;
                        valid_out <= 0; // Output is not valid during loading
                    end
                end
                COMPUTE: begin
                    // Calculate and output the pooled result
                    data_out <= pool_result;
                    valid_out <= 1; // Mark the output as valid
                    output_counter <= output_counter + 1;
                end
                DONE: begin
                    // Indicate that pooling operations are complete
                    done <= 1;
                    valid_out <= 0; // No more valid output
                end
            endcase
        end
    end

    // Logic to determine the next state in the state machine
    always @(*) begin
        case (state)
            IDLE: next_state = en ? LOAD : IDLE; // Start loading data if enabled
            LOAD: next_state = (input_counter == p*p - 1) ? COMPUTE : LOAD;
                   // Move to compute once all data for the pool window is loaded
            COMPUTE: next_state = (output_counter == (m/p)*(m/p) - 1) ? DONE : LOAD;
                     // After computing the output, return to load more data or finish if done
            DONE: next_state = IDLE; // Return to IDLE state
            default: next_state = IDLE; // Default to IDLE in case of unexpected states
        endcase
    end
endmodule
