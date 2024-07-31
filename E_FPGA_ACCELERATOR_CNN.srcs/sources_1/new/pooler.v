`timescale 1ns / 1ps

module pooler #(
    parameter N = 16,     // Bit width of activations (16-bit precision balances accuracy and hardware efficiency)
    parameter m = 4,      // Size of the input feature map (4x4 in this case, adjustable for different input sizes)
    parameter p = 2       // Size of the pooling window (2x2 is standard for reducing spatial dimensions while retaining important features)
)(
    input wire clk,              // Clock signal for synchronizing operations
    input wire rst,              // Reset signal for initializing the module
    input wire en,               // Enable signal to start processing
    input wire [N-1:0] data_in,  // Input data stream
    input wire [1:0] pool_type,  // Selects pooling operation: 00: max, 01: avg, 10: min
    output reg [N-1:0] data_out, // Output data after pooling
    output reg valid_out,        // Indicates when the output data is valid
    output reg done              // Signals the completion of all pooling operations
);
    // Pooling window buffer: Stores p*p elements for the current pooling operation
    reg [N-1:0] pool_buffer [p*p-1:0];
    
    // Counters for tracking progress
    reg [$clog2(m*m)-1:0] input_counter;     // Counts input elements
    reg [$clog2((m/p)*(m/p))-1:0] output_counter; // Counts output elements
    
    // State machine for controlling the pooling process
    localparam IDLE = 2'b00, LOAD = 2'b01, COMPUTE = 2'b10, DONE = 2'b11;
    reg [1:0] state, next_state;

    integer i; // Loop variable

    // Pooling computation logic
    reg [N-1:0] pool_result;
    always @(*) begin
        case (pool_type)
            2'b00: begin // Max pooling
                pool_result = pool_buffer[0];
                for (i = 1; i < p*p; i = i + 1) begin
                    if ($signed(pool_buffer[i]) > $signed(pool_result))
                        pool_result = pool_buffer[i];
                end
            end
            2'b01: begin // Average pooling
                pool_result = 0;
                for (i = 0; i < p*p; i = i + 1) begin
                    pool_result = pool_result + pool_buffer[i];
                end
                pool_result = pool_result / (p*p); // Simple average, may need rounding in practice
            end
            2'b10: begin // Min pooling
                pool_result = pool_buffer[0];
                for (i = 1; i < p*p; i = i + 1) begin
                    if ($signed(pool_buffer[i]) < $signed(pool_result))
                        pool_result = pool_buffer[i];
                end
            end
            default: pool_result = pool_buffer[0]; // Fallback to prevent latch inference
        endcase
    end

    // State machine and control logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all registers and counters
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
            state <= next_state;
            case (state)
                IDLE: begin
                    if (en) begin
                        // Initialize counters and flags when enabled
                        input_counter <= 0;
                        output_counter <= 0;
                        valid_out <= 0;
                        done <= 0;
                    end
                end
                LOAD: begin
                    if (en) begin
                        // Load input data into pooling buffer
                        pool_buffer[input_counter] <= data_in;
                        input_counter <= input_counter + 1;
                        valid_out <= 0;
                    end
                end
                COMPUTE: begin
                    // Perform pooling operation and output result
                    data_out <= pool_result;
                    valid_out <= 1;
                    output_counter <= output_counter + 1;
                end
                DONE: begin
                    // Signal completion of pooling operation
                    done <= 1;
                    valid_out <= 0;
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        case (state)
            IDLE: next_state = en ? LOAD : IDLE;
            LOAD: next_state = (input_counter == p*p - 1) ? COMPUTE : LOAD;
            COMPUTE: next_state = (output_counter == (m/p)*(m/p) - 1) ? DONE : LOAD;
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule