`default_nettype none

// Synchronous byte interface:
// Input: 32 key bytes followed by 16 plaintext bytes.
// Bytes within each 32-bit word use little-endian order.
// Nonce and counter are fixed to the FPGA wrapper's values.
module tt_um_dinis_chacha20 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    reg [383:0] frame;
    reg [5:0] count;
    reg [3:0] out_index;
    reg busy, valid, error, start;

    wire abort_cmd = uio_in[3];
    wire reset = !rst_n || !ena || abort_cmd;

    wire [255:0] key;
    wire [95:0] nonce = 96'h000000000000004A00000000;
    wire [31:0] counter = 32'h00000001;
    wire [127:0] plaintext, ciphertext;
    wire done;

    function [31:0] le_word;
        input [31:0] x;
        begin
            le_word = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : key_words
            assign key[255-32*i -:32] =
                le_word(frame[383-32*i -:32]);
        end

        for (i = 0; i < 4; i = i + 1) begin : data_words
            assign plaintext[127-32*i -:32] =
                le_word(frame[127-32*i -:32]);
        end
    endgenerate

    chacha20_core core (
        .clk      (clk),
        .rst      (reset),
        .start    (start),
        .key      (key),
        .nonce    (nonce),
        .counter  (counter),
        .data_in  (plaintext),
        .data_out (ciphertext),
        .done     (done)
    );

    // Convert packed core words to little-endian stream bytes.
    wire [6:0] output_bit =
        7'd96 - {out_index[3:2], 5'b0}
              + {2'b0, out_index[1:0], 3'b0};

    assign uo_out = (ena && valid)
                  ? ciphertext[output_bit +:8]
                  : 8'b0;

    // uio[7:4]: error, valid, ready, busy.
    // uio[3:0]: abort, next, start, load.
    assign uio_out = {
        error,
        valid,
        (!busy && count == 6'd48),
        busy,
        4'b0
    };

    assign uio_oe = ena ? 8'hf0 : 8'h00;

    wire _unused = &{1'b0, uio_in[7:4]};

    always @(posedge clk) begin
        if (reset) begin
            frame     <= 0;
            count     <= 0;
            out_index <= 0;
            busy      <= 0;
            valid     <= 0;
            error     <= 0;
            start     <= 0;
        end else begin
            start <= 0;

            if (done && busy) begin
                busy      <= 0;
                valid     <= 1;
                out_index <= 0;
            end

            case (uio_in[2:0])
                3'b000: begin
                    // Idle.
                end

                3'b001: begin
                    // Load one byte per asserted clock.
                    if (!busy && count < 6'd48) begin
                        frame <= {frame[375:0], ui_in};
                        count <= count + 1'b1;
                    end else begin
                        error <= 1;
                    end
                end

                3'b010: begin
                    // Start after all 48 bytes have been loaded.
                    if (!busy && count == 6'd48) begin
                        start     <= 1;
                        busy      <= 1;
                        valid     <= 0;
                        count     <= 0;
                        out_index <= 0;
                    end else begin
                        error <= 1;
                    end
                end

                3'b100: begin
                    // Sample the current output byte BEFORE this edge.
                    if (valid) begin
                        if (out_index == 4'd15) begin
                            valid     <= 0;
                            out_index <= 0;
                        end else begin
                            out_index <= out_index + 1'b1;
                        end
                    end else begin
                        error <= 1;
                    end
                end

                default: begin
                    // Ignore conflicting commands and flag an error.
                    error <= 1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire