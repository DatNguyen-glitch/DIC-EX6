
module Attention(
    rst_n,
    clk,
    Input_valid,
    Input,   

    Out_valid,
    Out

);

input            rst_n;
input            clk;
input            Input_valid;
input            [15:0]Input; 

output reg       Out_valid;
output reg       [15:0] Out; 

// parameter /////////////////////////
parameter sig_width = 10;
parameter exp_width = 5;
parameter ieee_compliance = 0;
parameter faithful_round = 0;
parameter arch = 2;

parameter IDLE = 'd0;
parameter INPUT_Q = 'd1;
parameter INPUT_K = 'd2;
parameter MULT = 'd3;
parameter ADD = 'd4;
parameter EXP = 'd5;
parameter DIV = 'd6;
parameter ACC = 'd8;
parameter OUTPUT = 'd9;
integer i,j;

// reg ///////////////////////////////
// register
reg [3:0]state , n_state ;
reg [3:0]cnt;
reg [3:0]cnt_mult;
reg [15:0] Matrix_Q [3:0][3:0];
reg [15:0] Matrix_K [3:0][3:0];
reg [15:0] mult_result [3:0];
reg [15:0] add_result;
reg [15:0] QKT  [3:0][3:0];
reg [15:0] acc_result;

// wire //////////////////////////////
reg [15:0] mult_a[3:0];
reg [15:0] mult_b[3:0];
wire [3:0]cnt_exp;
wire [3:0] cnt_div;
wire [15:0] Out_comb;
wire [15:0] add_result_comb_1 [1:0];
wire [15:0] add_result_comb_2;
wire [15:0] exp_result_comb;
wire [15:0] acc_result_comb;
wire [15:0] mult_result_comb [3:0];

//////////////////////////////////////

assign cnt_exp = (state == ACC) ? (cnt + 1) : 0;
assign cnt_div = (state == OUTPUT) ? (cnt + 1) : 0; 
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        state <= IDLE;
    end
    else begin
        state <= n_state;
    end
end
always @(*) begin
    case (state)
        IDLE : begin
            n_state = Input_valid ? INPUT_Q : IDLE;
        end
        INPUT_Q : begin
            n_state = (cnt == 15) ? INPUT_K : INPUT_Q;
        end
        INPUT_K : begin
            n_state = (cnt == 15) ? MULT : INPUT_K;
        end
        MULT : begin
            n_state = ADD;
        end
        ADD : begin
            n_state = EXP;
        end
        EXP : begin
            n_state = ACC;
        end
        ACC : begin
            n_state = (cnt == 15) ? DIV : ACC;
        end
        DIV : begin
            n_state = OUTPUT;
        end
        OUTPUT : begin
            n_state = (cnt == 15) ? IDLE : OUTPUT;
        end
        default : begin
            n_state = state;
        end
    endcase
end
// cnt
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        cnt <= 0;
    end
    else begin
        if ((n_state == INPUT_Q) || (n_state == INPUT_K) || (n_state == MULT) ||( state == ACC) ||( state == OUTPUT)) cnt <= cnt + 1;
        else cnt <= 0;
    end
end
// cnt_mult
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
        cnt_mult <= 0;
    end
    else begin
        if ( state == MULT || cnt_mult != 0 ) cnt_mult <= cnt_mult + 1;
        else cnt_mult <= 0;
    end
end
// Matrix_Q
reg clock_en_q;
wire gated_clk_q;

always @(*) begin
    if((state == IDLE) || (state == INPUT_Q))
        clock_en_q = 1'b1;
    else
        clock_en_q = 1'b0;    
end

ICGx3_ASAP7_75t_R u_clkgating_01 (
    .GCLK(gated_clk_q),
    .ENA(1'b0),
    .SE(clock_en_q),
    .CLK(clk)
);

//always @(posedge clk or negedge rst_n) begin
always @(posedge gated_clk_q or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0;i < 4; i =i +1) begin
            for (j = 0;j < 4; j =j +1) begin
                Matrix_Q[i][j] <= 0 ;
            end
        end
    end
    else begin
        if (n_state == INPUT_Q || state == INPUT_Q) begin
            Matrix_Q[cnt[3:2]][cnt[1:0]] <= Input;
        end
        else if (state == IDLE)begin
            for (i = 0;i < 4; i =i +1) begin
                for (j = 0;j < 4; j =j +1) begin
                    Matrix_Q[i][j] <= 0 ;
                end
            end
        end
    end
end
// Matrix_K
reg clock_en_k;
wire gated_clk_k;

always @(*) begin
    if((state == IDLE) || (state == INPUT_K) || (n_state == IDLE) || (n_state == INPUT_K))
        clock_en_k = 1'b1;
    else
        clock_en_k = 1'b0;    
end

ICGx3_ASAP7_75t_R u_clkgating_02 (
    .GCLK(gated_clk_k),
    .ENA(1'b0),
    .SE(clock_en_k),
    .CLK(clk)
);

//always @(posedge clk or negedge rst_n) begin
always @(posedge gated_clk_k or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0;i < 4; i =i +1) begin
            for (j = 0;j < 4; j =j +1) begin
                Matrix_K[i][j] <= 0 ;
            end
        end
    end
    else begin
        if (state == INPUT_K) begin
            Matrix_K[cnt[3:2]][cnt[1:0]] <= Input;
        end
        else if (state == IDLE)begin
            for (i = 0;i < 4; i =i +1) begin
                for (j = 0;j < 4; j =j +1) begin
                    Matrix_K[i][j] <= 0 ;
                end
            end
        end
    end
end

// mult_a 
always @(*) begin
    if ((state == MULT  ||  cnt_mult > 0) ) begin
        mult_a[0] = Matrix_Q[cnt_mult[3:2]][0];
        mult_a[1] = Matrix_Q[cnt_mult[3:2]][1];
        mult_a[2] = Matrix_Q[cnt_mult[3:2]][2];
        mult_a[3] = Matrix_Q[cnt_mult[3:2]][3];
    end
    else begin
        mult_a[0] =  0;
        mult_a[1] =  0;    
        mult_a[2] =  0;    
        mult_a[3] =  0;    
    end
end
// mult_b
always @(*) begin
    if ((state == MULT  ||  cnt_mult > 0) ) begin
        mult_b[0] = Matrix_K[cnt_mult[1:0]][0];
        mult_b[1] = Matrix_K[cnt_mult[1:0]][1];
        mult_b[2] = Matrix_K[cnt_mult[1:0]][2];
        mult_b[3] = Matrix_K[cnt_mult[1:0]][3];
    end
    else begin
        mult_b[0] =  0;
        mult_b[1] =  0;    
        mult_b[2] =  0;    
        mult_b[3] =  0;    
    end
end
// mult_result
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mult_result[0] <= 0;
        mult_result[1] <= 0;
        mult_result[2] <= 0;
        mult_result[3] <= 0;
    end
    else begin
        mult_result[0] <= mult_result_comb[0];
        mult_result[1] <= mult_result_comb[1];
        mult_result[2] <= mult_result_comb[2];
        mult_result[3] <= mult_result_comb[3];
    end
end

// add_result
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        add_result <= 0;
    end
    else begin
        add_result <= add_result_comb_2;
    end
end
// QKT
reg clock_en_qkt;
wire gated_clk_qkt;

always @(*) begin
    if((state == IDLE) || (state == ACC) || (n_state == IDLE) || (n_state == ACC))
        clock_en_qkt = 1'b1;
    else
        clock_en_qkt = 1'b0;    
end

ICGx3_ASAP7_75t_R u_clkgating_03 (
    .GCLK(gated_clk_qkt),
    .ENA(1'b0),
    .SE(clock_en_qkt),
    .CLK(clk)
);

//always @(posedge clk or negedge rst_n) begin
always @(posedge gated_clk_qkt or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0;i < 4; i =i +1) begin
            for (j = 0;j < 4; j =j +1) begin
                QKT[i][j] <= 0 ;
            end
        end
    end
    else begin
        if ( n_state == ACC ) begin
            QKT[cnt_exp[3:2]][cnt_exp[1:0]] <= exp_result_comb;
        end
        else if (n_state == IDLE)begin
            for (i = 0;i < 4; i =i +1) begin
                for (j = 0;j < 4; j =j +1) begin
                    QKT[i][j] <= 0 ;
                end
            end
        end
    end
end
// acc_result
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc_result <= 0;
    end
    else begin
        if (state == ACC) begin
            acc_result <= acc_result_comb;
        end
        else if (state == IDLE) begin
            acc_result <= 0;
        end
        
    end
end
// Out
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Out <= 0;
    end
    else begin
        if (n_state == OUTPUT)begin
            Out <= Out_comb;
        end
        else begin
            Out <= 0;
        end
    end
end
// Out_valid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        Out_valid <= 0;
    end
    else begin
        if (n_state == OUTPUT)begin
            Out_valid <= 1;
        end
        else begin
            Out_valid <= 0;
        end
    end
end

// design ware
DW_fp_mult #(sig_width, exp_width, ieee_compliance) u_fp_mult_0(.a(mult_a[0]), .b(mult_b[0]), .rnd(3'd0),  .z(mult_result_comb[0]));
DW_fp_mult #(sig_width, exp_width, ieee_compliance) u_fp_mult_1(.a(mult_a[1]), .b(mult_b[1]), .rnd(3'd0),  .z(mult_result_comb[1]));
DW_fp_mult #(sig_width, exp_width, ieee_compliance) u_fp_mult_2(.a(mult_a[2]), .b(mult_b[2]), .rnd(3'd0),  .z(mult_result_comb[2]));
DW_fp_mult #(sig_width, exp_width, ieee_compliance) u_fp_mult_3(.a(mult_a[3]), .b(mult_b[3]), .rnd(3'd0),  .z(mult_result_comb[3]));
DW_fp_add  #(sig_width, exp_width, ieee_compliance) u_fp_add_0( .a(mult_result[0]),  .b(mult_result[1]), .rnd(3'd0), .z(add_result_comb_1[0])  );
DW_fp_add  #(sig_width, exp_width, ieee_compliance) u_fp_add_1( .a(mult_result[2]),  .b(mult_result[3]), .rnd(3'd0), .z(add_result_comb_1[1])  );
DW_fp_add  #(sig_width, exp_width, ieee_compliance) u_fp_add_2( .a(add_result_comb_1[0]),  .b(add_result_comb_1[1]), .rnd(3'd0), .z(add_result_comb_2)  );
DW_fp_add  #(sig_width, exp_width, ieee_compliance) u_fp_add_3( .a(QKT[cnt[3:2]][cnt[1:0]]),  .b(acc_result), .rnd(3'd0), .z(acc_result_comb)  );
DW_fp_exp  #(sig_width, exp_width, ieee_compliance, arch) u_fp_exp ( .a(add_result), .z(exp_result_comb) );
DW_fp_div  #(sig_width, exp_width, ieee_compliance, faithful_round) u_fp_div (.a(QKT[cnt_div[3:2]][cnt_div[1:0]]),.b(acc_result), .rnd(3'd0), .z(Out_comb));
endmodule



