`default_nettype none

// ChaCha20 with one shared 32-bit datapath adder.
//
// Each quarter-round takes four clocks.
// 80 quarter-rounds * 4 clocks + 4 feed-forward clocks = 324.
//
// Inputs are captured when start is accepted in ST_IDLE.
// start is ignored while computing.
// done pulses for one clock.
// data_out remains unchanged until the complete result is ready.
//
// Synchronous active-high reset.
//
// Packing:
//   state word 0 = [511:480]
//   key word 0   = [255:224]
//
// Produces the first 128 ciphertext bits.

module chacha20_core (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,

    input  wire [127:0] data_in,
    input  wire [255:0] key,
    input  wire [95:0]  nonce,
    input  wire [31:0]  counter,

    output reg  [127:0] data_out,
    output reg          done
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_RUN   = 2'd1;
    localparam [1:0] ST_FINAL = 2'd2;

    localparam [31:0] C0 = 32'h61707865;
    localparam [31:0] C1 = 32'h3320646e;
    localparam [31:0] C2 = 32'h79622d32;
    localparam [31:0] C3 = 32'h6b206574;

    reg [1:0] state_ctrl;
    reg [4:0] round_index;
    reg [1:0] qr_index;
    reg [1:0] qr_step;

    reg [511:0] working_state;

    // Stores plaintext, then accumulates ciphertext during ST_FINAL.
    reg [127:0] data_reg;

    wire [511:0] input_state = {
        C0, C1, C2, C3,
        key,
        counter,
        nonce
    };

    wire [127:0] bank_a = working_state[511:384];
    wire [127:0] bank_b = working_state[383:256];
    wire [127:0] bank_c = working_state[255:128];
    wire [127:0] bank_d = working_state[127:0];

    // Even rounds are column rounds; odd rounds are diagonal rounds.
    wire use_diagonal = round_index[0];

    wire [1:0] sel_a = qr_index;
    wire [1:0] sel_b =
        qr_index + (use_diagonal ? 2'd1 : 2'd0);
    wire [1:0] sel_c =
        qr_index + (use_diagonal ? 2'd2 : 2'd0);
    wire [1:0] sel_d =
        qr_index + (use_diagonal ? 2'd3 : 2'd0);

    wire [31:0] word_a = bank_a[127-32*sel_a -:32];
    wire [31:0] word_b = bank_b[127-32*sel_b -:32];
    wire [31:0] word_c = bank_c[127-32*sel_c -:32];
    wire [31:0] word_d = bank_d[127-32*sel_d -:32];

    reg [31:0] final_constant;

    always @* begin
        case (qr_index)
            2'd0: final_constant = C0;
            2'd1: final_constant = C1;
            2'd2: final_constant = C2;
            2'd3: final_constant = C3;
            default: final_constant = C0;
        endcase
    end

    // Steps 0 and 2: a + b.
    // Steps 1 and 3: c + d.
    // ST_FINAL: selected state word + its initial constant.
    wire [31:0] add_left =
        (state_ctrl == ST_FINAL) ? word_a :
        (qr_step[0] ? word_c : word_a);

    wire [31:0] add_right =
        (state_ctrl == ST_FINAL) ? final_constant :
        (qr_step[0] ? word_d : word_b);

    // The single shared 32-bit datapath adder.
    wire [31:0] add_result = add_left + add_right;

    wire [31:0] xor_operand = qr_step[0] ? word_b : word_d;
    wire [31:0] xor_result = xor_operand ^ add_result;

    reg [31:0] rotated_result;

    always @* begin
        case (qr_step)
            // ROTL 16.
            2'd0: rotated_result =
                {xor_result[15:0], xor_result[31:16]};

            // ROTL 12.
            2'd1: rotated_result =
                {xor_result[19:0], xor_result[31:20]};

            // ROTL 8.
            2'd2: rotated_result =
                {xor_result[23:0], xor_result[31:24]};

            // ROTL 7.
            2'd3: rotated_result =
                {xor_result[24:0], xor_result[31:25]};

            default: rotated_result = 32'd0;
        endcase
    end

    wire [31:0] plaintext_word =
        data_reg[127-32*qr_index -:32];

    wire [31:0] ciphertext_word = plaintext_word ^ add_result;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state_ctrl    <= ST_IDLE;
            round_index   <= 5'd0;
            qr_index      <= 2'd0;
            qr_step       <= 2'd0;
            working_state <= 512'd0;
            data_reg      <= 128'd0;
            data_out      <= 128'd0;
            done          <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state_ctrl)
                ST_IDLE: begin
                    if (start) begin
                        working_state <= input_state;
                        data_reg      <= data_in;
                        round_index   <= 5'd0;
                        qr_index      <= 2'd0;
                        qr_step       <= 2'd0;
                        state_ctrl    <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    // Update two selected words per clock.
                    // Other words retain their values.
                    for (i = 0; i < 4; i = i + 1) begin
                        if (!qr_step[0]) begin
                            // a = a + b
                            // d = ROTL(d XOR a, 16 or 8)
                            if (sel_a == i[1:0])
                                working_state[511-32*i -:32]
                                    <= add_result;

                            if (sel_d == i[1:0])
                                working_state[127-32*i -:32]
                                    <= rotated_result;
                        end else begin
                            // c = c + d
                            // b = ROTL(b XOR c, 12 or 7)
                            if (sel_c == i[1:0])
                                working_state[255-32*i -:32]
                                    <= add_result;

                            if (sel_b == i[1:0])
                                working_state[383-32*i -:32]
                                    <= rotated_result;
                        end
                    end

                    if (qr_step == 2'd3) begin
                        qr_step <= 2'd0;

                        if (qr_index == 2'd3) begin
                            qr_index <= 2'd0;

                            if (round_index == 5'd19) begin
                                state_ctrl <= ST_FINAL;
                            end else begin
                                round_index <= round_index + 5'd1;
                            end
                        end else begin
                            qr_index <= qr_index + 2'd1;
                        end
                    end else begin
                        qr_step <= qr_step + 2'd1;
                    end
                end

                ST_FINAL: begin
                    // Reuse the same adder for feed-forward.
                    // Each plaintext word is read before being replaced.
                    if (qr_index == 2'd3) begin
                        // First three ciphertext words were saved earlier.
                        // Publish all four words together.
                        data_out <= {
                            data_reg[127:32],
                            ciphertext_word
                        };
                        done       <= 1'b1;
                        qr_index   <= 2'd0;
                        state_ctrl <= ST_IDLE;
                    end else begin
                        data_reg[127-32*qr_index -:32]
                            <= ciphertext_word;
                        qr_index <= qr_index + 2'd1;
                    end
                end

                default: begin
                    state_ctrl  <= ST_IDLE;
                    round_index <= 5'd0;
                    qr_index    <= 2'd0;
                    qr_step     <= 2'd0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire