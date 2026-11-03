function [5:0] first_caption;input [2:0] track;begin case(track)
3'd1:first_caption=6'd1;
3'd2:first_caption=6'd11;
3'd3:first_caption=6'd22;
3'd4:first_caption=6'd31;
default:first_caption=0;endcase end endfunction
function [5:0] last_caption;input [2:0] track;begin case(track)
3'd1:last_caption=6'd10;
3'd2:last_caption=6'd21;
3'd3:last_caption=6'd30;
3'd4:last_caption=6'd42;
default:last_caption=0;endcase end endfunction
