`default_nettype none

// Iterative ChaCha20: one complete quarter-round per clock.
// 80 QR cycles + 1 final output cycle.
// Synchronous active-high reset.
// Encrypts 128 bits using the first four feed-forward words.
//
// Packing:
//   state word 0 = [511:480]
//   key word 0   = [255:224]

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

    localparam [1:0] ST_IDLE     = 2'd0;
    localparam [1:0] ST_COLUMN   = 2'd1;
    localparam [1:0] ST_DIAGONAL = 2'd2;
    localparam [1:0] ST_FINAL    = 2'd3;

    // ChaCha20 constants: "expand 32-byte k".
    localparam [31:0] C0 = 32'h61707865;
    localparam [31:0] C1 = 32'h3320646e;
    localparam [31:0] C2 = 32'h79622d32;
    localparam [31:0] C3 = 32'h6b206574;

    reg [1:0] state_ctrl;
    reg [1:0] qr_index;
    reg [3:0] double_round_count;

    reg [511:0] working_state;
    reg [511:0] working_next;
    reg [127:0] data_reg;

    wire [511:0] input_state;

    assign input_state = {
        C0, C1, C2, C3,
        key,
        counter,
        nonce
    };

    // Four banks, each containing four 32-bit words.
    wire [127:0] bank_a = working_state[511:384];
    wire [127:0] bank_b = working_state[383:256];
    wire [127:0] bank_c = working_state[255:128];
    wire [127:0] bank_d = working_state[127:0];

    wire use_diagonal = (state_ctrl == ST_DIAGONAL);

    // Two-bit selectors wrap modulo four.
    wire [1:0] sel_a = qr_index;

    wire [1:0] sel_b =
        qr_index + (use_diagonal ? 2'd1 : 2'd0);

    wire [1:0] sel_c =
        qr_index + (use_diagonal ? 2'd2 : 2'd0);

    wire [1:0] sel_d =
        qr_index + (use_diagonal ? 2'd3 : 2'd0);

    wire [31:0] qr_a = bank_a[127-32*sel_a -:32];
    wire [31:0] qr_b = bank_b[127-32*sel_b -:32];
    wire [31:0] qr_c = bank_c[127-32*sel_c -:32];
    wire [31:0] qr_d = bank_d[127-32*sel_d -:32];

    wire [31:0] qr_a_out;
    wire [31:0] qr_b_out;
    wire [31:0] qr_c_out;
    wire [31:0] qr_d_out;

    chacha20_qr_iter1 qr_inst (
        .a     (qr_a),
        .b     (qr_b),
        .c     (qr_c),
        .d     (qr_d),
        .a_out (qr_a_out),
        .b_out (qr_b_out),
        .c_out (qr_c_out),
        .d_out (qr_d_out)
    );

    // Preserve twelve words and update the selected four.
    integer i;

    always @* begin
        working_next = working_state;

        for (i = 0; i < 4; i = i + 1) begin
            if (sel_a == i[1:0])
                working_next[511-32*i -:32] = qr_a_out;

            if (sel_b == i[1:0])
                working_next[383-32*i -:32] = qr_b_out;

            if (sel_c == i[1:0])
                working_next[255-32*i -:32] = qr_c_out;

            if (sel_d == i[1:0])
                working_next[127-32*i -:32] = qr_d_out;
        end
    end

    // Only the first four output words are required.
    // Their original state values are always C0 through C3.
    // Each addition is modulo 2^32.
    wire [31:0] f0 = working_state[511:480] + C0;
    wire [31:0] f1 = working_state[479:448] + C1;
    wire [31:0] f2 = working_state[447:416] + C2;
    wire [31:0] f3 = working_state[415:384] + C3;

    wire [127:0] keystream_128 = {f0, f1, f2, f3};

    always @(posedge clk) begin
        if (rst) begin
            state_ctrl         <= ST_IDLE;
            qr_index           <= 2'd0;
            double_round_count <= 4'd0;
            working_state      <= 512'd0;
            data_reg           <= 128'd0;
            data_out           <= 128'd0;
            done               <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state_ctrl)
                ST_IDLE: begin
                    if (start) begin
                        working_state      <= input_state;
                        data_reg           <= data_in;
                        qr_index           <= 2'd0;
                        double_round_count <= 4'd0;
                        state_ctrl         <= ST_COLUMN;
                    end
                end

                ST_COLUMN: begin
                    working_state <= working_next;

                    if (qr_index == 2'd3) begin
                        qr_index   <= 2'd0;
                        state_ctrl <= ST_DIAGONAL;
                    end else begin
                        qr_index <= qr_index + 2'd1;
                    end
                end

                ST_DIAGONAL: begin
                    working_state <= working_next;

                    if (qr_index == 2'd3) begin
                        qr_index <= 2'd0;

                        if (double_round_count == 4'd9) begin
                            state_ctrl <= ST_FINAL;
                        end else begin
                            double_round_count <=
                                double_round_count + 4'd1;
                            state_ctrl <= ST_COLUMN;
                        end
                    end else begin
                        qr_index <= qr_index + 2'd1;
                    end
                end

                ST_FINAL: begin
                    data_out   <= data_reg ^ keystream_128;
                    done       <= 1'b1;
                    state_ctrl <= ST_IDLE;
                end

                default: begin
                    state_ctrl         <= ST_IDLE;
                    qr_index           <= 2'd0;
                    double_round_count <= 4'd0;
                end
            endcase
        end
    end

endmodule


// Combinational ChaCha20 quarter-round.
module chacha20_qr_iter1 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [31:0] d,

    output wire [31:0] a_out,
    output wire [31:0] b_out,
    output wire [31:0] c_out,
    output wire [31:0] d_out
);

    wire [31:0] a1, b1, c1, d1;
    wire [31:0] a2, b2, c2, d2;
    wire [31:0] dx1, bx1, dx2, bx2;

    // a += b; d ^= a; rotate d left by 16.
    assign a1  = a + b;
    assign dx1 = d ^ a1;
    assign d1  = {dx1[15:0], dx1[31:16]};

    // c += d; b ^= c; rotate b left by 12.
    assign c1  = c + d1;
    assign bx1 = b ^ c1;
    assign b1  = {bx1[19:0], bx1[31:20]};

    // a += b; d ^= a; rotate d left by 8.
    assign a2  = a1 + b1;
    assign dx2 = d1 ^ a2;
    assign d2  = {dx2[23:0], dx2[31:24]};

    // c += d; b ^= c; rotate b left by 7.
    assign c2  = c1 + d2;
    assign bx2 = b1 ^ c2;
    assign b2  = {bx2[24:0], bx2[31:25]};

    assign a_out = a2;
    assign b_out = b2;
    assign c_out = c2;
    assign d_out = d2;

endmodule

`default_nettype wire