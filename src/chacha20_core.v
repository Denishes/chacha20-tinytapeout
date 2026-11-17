// 1QR.v
//
// Iterative ChaCha20: one complete quarter-round per clock cycle.
//
// 20 rounds x 4 QR operations = 80 QR cycles.
// Latency: 81 cycles from accepted start to done.
// Initiation interval: 82 cycles with start continuously asserted.
//
// A request is accepted only in ST_IDLE.
// Inputs are captured at acceptance.
// start is ignored while the core is busy.
//
// data_out holds its value until another result is produced.
// done is asserted for one cycle when data_out becomes valid.
//
// Synchronous active-high reset aborts the current operation.
//
// Same packing as the existing cores:
//   state word 0 = [511:480]
//   key word 0   = [255:224]
//
// The interface encrypts 128 bits using the first four
// feed-forward state words.
//
// All helper logic is included below.

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

    // Selects one of the four QRs within the current round.
    reg [1:0] qr_index;

    // Counts the ten column/diagonal pairs: 0..9.
    reg [3:0] double_round_count;

    reg [511:0] initial_state;
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

    // Each bank contains four 32-bit words:
    //
    // bank_a: s0,  s1,  s2,  s3
    // bank_b: s4,  s5,  s6,  s7
    // bank_c: s8,  s9,  s10, s11
    // bank_d: s12, s13, s14, s15

    wire [127:0] bank_a = working_state[511:384];
    wire [127:0] bank_b = working_state[383:256];
    wire [127:0] bank_c = working_state[255:128];
    wire [127:0] bank_d = working_state[127:0];

    wire use_diagonal = (state_ctrl == ST_DIAGONAL);

    // Two-bit results wrap modulo 4.
    //
    // Columns:
    //   a=q, b=q, c=q, d=q within their respective banks.
    //
    // Diagonals:
    //   a=q, b=q+1, c=q+2, d=q+3 modulo 4.

    wire [1:0] sel_a = qr_index;

    wire [1:0] sel_b =
        qr_index + (use_diagonal ? 2'd1 : 2'd0);

    wire [1:0] sel_c =
        qr_index + (use_diagonal ? 2'd2 : 2'd0);

    wire [1:0] sel_d =
        qr_index + (use_diagonal ? 2'd3 : 2'd0);

    // Select the four words processed during this cycle.
    wire [31:0] qr_a = bank_a[127-32*sel_a -: 32];
    wire [31:0] qr_b = bank_b[127-32*sel_b -: 32];
    wire [31:0] qr_c = bank_c[127-32*sel_c -: 32];
    wire [31:0] qr_d = bank_d[127-32*sel_d -: 32];

    wire [31:0] qr_a_out;
    wire [31:0] qr_b_out;
    wire [31:0] qr_c_out;
    wire [31:0] qr_d_out;

    // Exactly one physical QR instance.
    chacha20_qr_iter1 qr_inst (
        .a(qr_a),
        .b(qr_b),
        .c(qr_c),
        .d(qr_d),

        .a_out(qr_a_out),
        .b_out(qr_b_out),
        .c_out(qr_c_out),
        .d_out(qr_d_out)
    );

    // Preserve twelve words and replace the four selected words.
    //
    // This loop describes write selection.
    // It does not instantiate additional QR units.
    integer i;

    always @* begin
        working_next = working_state;

        for (i = 0; i < 4; i = i + 1) begin
            if (sel_a == i)
                working_next[511-32*i -: 32] = qr_a_out;

            if (sel_b == i)
                working_next[383-32*i -: 32] = qr_b_out;

            if (sel_c == i)
                working_next[255-32*i -: 32] = qr_c_out;

            if (sel_d == i)
                working_next[127-32*i -: 32] = qr_d_out;
        end
    end

    // Final feed-forward for the 128 useful output bits.
    // Each addition is modulo 2^32.
    wire [31:0] f0 =
        working_state[511:480] + initial_state[511:480];

    wire [31:0] f1 =
        working_state[479:448] + initial_state[479:448];

    wire [31:0] f2 =
        working_state[447:416] + initial_state[447:416];

    wire [31:0] f3 =
        working_state[415:384] + initial_state[415:384];

    wire [127:0] keystream_128 = {f0, f1, f2, f3};

    always @(posedge clk) begin
        if (rst) begin
            state_ctrl         <= ST_IDLE;
            qr_index           <= 2'd0;
            double_round_count <= 4'd0;

            initial_state      <= 512'd0;
            working_state      <= 512'd0;
            data_reg           <= 128'd0;

            data_out           <= 128'd0;
            done               <= 1'b0;

        end else begin
            // Default: done is a one-cycle pulse.
            done <= 1'b0;

            case (state_ctrl)

                ST_IDLE: begin
                    if (start) begin
                        initial_state      <= input_state;
                        working_state      <= input_state;
                        data_reg           <= data_in;

                        qr_index           <= 2'd0;
                        double_round_count <= 4'd0;

                        state_ctrl         <= ST_COLUMN;
                    end
                end

                ST_COLUMN: begin
                    // Commit one complete column QR.
                    working_state <= working_next;

                    if (qr_index == 2'd3) begin
                        // All four column QRs are complete.
                        qr_index   <= 2'd0;
                        state_ctrl <= ST_DIAGONAL;
                    end else begin
                        qr_index <= qr_index + 2'd1;
                    end
                end

                ST_DIAGONAL: begin
                    // Commit one complete diagonal QR.
                    working_state <= working_next;

                    if (qr_index == 2'd3) begin
                        // A complete double-round has finished.
                        qr_index <= 2'd0;

                        if (double_round_count == 4'd9) begin
                            // Ten double-rounds = twenty rounds.
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
                    // working_state already includes the final QR.
                    data_out <= data_reg ^ keystream_128;
                    done     <= 1'b1;

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
// Unique module name avoids conflicts with src/chacha20_qr.v.
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

    wire [31:0] dx1, bx1;
    wire [31:0] dx2, bx2;

    // a += b; d ^= a; d = ROTL(d,16);
    assign a1  = a + b;
    assign dx1 = d ^ a1;
    assign d1  = {dx1[15:0], dx1[31:16]};

    // c += d; b ^= c; b = ROTL(b,12);
    assign c1  = c + d1;
    assign bx1 = b ^ c1;
    assign b1  = {bx1[19:0], bx1[31:20]};

    // a += b; d ^= a; d = ROTL(d,8);
    assign a2  = a1 + b1;
    assign dx2 = d1 ^ a2;
    assign d2  = {dx2[23:0], dx2[31:24]};

    // c += d; b ^= c; b = ROTL(b,7);
    assign c2  = c1 + d2;
    assign bx2 = b1 ^ c2;
    assign b2  = {bx2[24:0], bx2[31:25]};

    assign a_out = a2;
    assign b_out = b2;
    assign c_out = c2;
    assign d_out = d2;

endmodule
