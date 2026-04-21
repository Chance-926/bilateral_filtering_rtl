// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module fifo_filter (
	clock,
	data,
	rdreq,
	wrreq,
	sclr,
	q
	);

	input    clock;
	input    [7:0]    data;
	input    rdreq;
	input    wrreq;
	input    sclr;
	output    [7:0]    q;

	scfifo    scfifo (
		.clock (clock),
		.sclr (sclr),
		.wrreq (wrreq),
		.aclr (),
		.data (data),
		.rdreq (rdreq),
		.usedw (),
		.empty (),
		.full (),
		.q (q),
		.almost_empty (),
		.almost_full ()
	);

	defparam
		scfifo.add_ram_output_register = "OFF",
		scfifo.intended_device_family = "Stratix",
		scfifo.lpm_hint = "RAM_BLOCK_TYPE=M4K",
		scfifo.lpm_numwords = 2048,
		scfifo.lpm_showahead = "ON",
		scfifo.lpm_type = "scfifo",
		scfifo.lpm_width = 8,
		scfifo.lpm_widthu = 11,
		scfifo.overflow_checking = "ON",
		scfifo.underflow_checking = "ON",
		scfifo.use_eab = "ON";
endmodule