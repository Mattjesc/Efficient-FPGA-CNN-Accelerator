`timescale 1ns / 1ps

// Testbench for the CNN accelerator
module accelerator_tb;
    // Parameters matching those in the accelerator module
    parameter N = 16;     // Bit width of activations and weights
    parameter Q = 12;     // Number of fractional bits
    parameter n = 6;      // Size of the input image/activation map
    parameter k = 3;      // Size of the convolution window
    parameter p = 2;      // Size of the pooling window
    parameter s = 1;      // Stride value during convolution
    parameter NUM_MAC = 4; // Number of parallel MAC units

    // Testbench signals
    reg clk;
    reg rst;
    reg en;
    reg [N-1:0] activation_in;
    reg [(k*k)*N-1:0] weight;
    reg [1:0] pool_type;
    wire [N-1:0] data_out;
    wire valid_out;
    wire done;

    // Instantiate the accelerator module (Unit Under Test)
    accelerator #(
        .N(N), .Q(Q), .n(n), .k(k), .p(p), .s(s), .NUM_MAC(NUM_MAC)
    ) uut (
        .clk(clk), .rst(rst), .en(en), .activation_in(activation_in),
        .weight(weight), .pool_type(pool_type), .data_out(data_out),
        .valid_out(valid_out), .done(done)
    );

    // Clock generation
    always #5 clk = ~clk; // Generate a clock with 10ns period

    // Test vectors
    reg [N-1:0] test_activation [0:(n*n)-1];
    reg [N-1:0] test_weights [0:(k*k)-1];
    integer i, error_count;

    // Simple pseudo-random number generator for test data
    reg [31:0] lfsr;
    function [31:0] pseudo_random;
        input [31:0] seed;
        begin
            lfsr = seed;
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            pseudo_random = lfsr;
        end
    endfunction

    // Task to initialize test vectors
    task initialize_test_vectors;
        input [31:0] seed;
        begin
            for (i = 0; i < n*n; i = i + 1) begin
                test_activation[i] = pseudo_random(seed + i);
            end
            for (i = 0; i < k*k; i = i + 1) begin
                test_weights[i] = pseudo_random(seed + n*n + i);
            end
        end
    endtask

    // Task to run a single test
    task run_test;
        input [1:0] p_type;
        input [31:0] seed;
        begin
            error_count = 0;
            initialize_test_vectors(seed);
            
            pool_type = p_type;
            rst = 1;
            #20;
            rst = 0;
            en = 1;

            // Load weights
            for (i = 0; i < k*k; i = i + 1) begin
                weight[i*N +: N] = test_weights[i];
            end

            // Feed activation inputs
            for (i = 0; i < n*n; i = i + 1) begin
                activation_in = test_activation[i];
                #10; // Wait for one clock cycle
            end

            // Wait for operation to complete
            wait(done);
            #100;
            
            $display("Test completed for pool_type %d with seed %d", p_type, seed);
        end
    endtask

    // Task to check output against expected values
    // Note: This is a placeholder. In a real scenario, you would compute expected values
    task check_output;
        input [N-1:0] expected;
        begin
            if (data_out !== expected) begin
                $display("Error: Expected %h, got %h", expected, data_out);
                error_count = error_count + 1;
            end
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        en = 0;
        activation_in = 0;
        weight = 0;
        pool_type = 2'b00;

        // Run tests for each pooling type with different seeds
        run_test(2'b00, 12345); // Max pooling
        run_test(2'b01, 67890); // Average pooling
        run_test(2'b10, 24680); // Min pooling

        // Edge case: All zeros
        initialize_test_vectors(0);
        run_test(2'b00, 0);

        // Edge case: All ones
        for (i = 0; i < n*n; i = i + 1) test_activation[i] = {N{1'b1}};
        for (i = 0; i < k*k; i = i + 1) test_weights[i] = {N{1'b1}};
        run_test(2'b01, 1);

        // Stress test: Rapid switching between pooling types
        for (i = 0; i < 10; i = i + 1) begin
            run_test(i % 3, i * 1000);
        end

        #100;
        $display("All tests completed. Total errors: %d", error_count);
        $finish;
    end

    // Monitor and logging
    always @(posedge clk) begin
        // State and Data Logging
        if (valid_out) begin
            $display("Time %t: Valid Output - data_out = %h", $time, data_out);
        end
        if (done) begin
            $display("Time %t: End of Operation", $time);
        end
    end

endmodule