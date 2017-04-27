#!/usr/bin/python

code ={};
def populatecode():
	code[8] = {};
	code8 = code[8];
	code8["stage"] = 6;
	code8[0] = [];
	code8[0].append([0,7]);
	code8[0].append([1,6]);
	code8[0].append([2,5]);
	code8[0].append([3,4]);
	
	code8[1] = [];
	code8[1].append([0,3]);
	code8[1].append([4,7]);
	code8[1].append([1,2]);
	code8[1].append([5,6]);
	
	code8[2] = [];
	code8[2].append([0,1]);
	code8[2].append([2,3]);
	code8[2].append([4,5]);
	code8[2].append([6,7]);
	
	code8[3] = [];
	code8[3].append([3,5]);
	code8[3].append([2,4]);
	
	code8[4] = [];
	code8[4].append([1,2]);
	code8[4].append([3,4]);
	code8[4].append([5,6]);
	
	code8[5] = [];
	code8[5].append([2,3]);
	code8[5].append([4,5]);

	#######################
	code[4] = {};
	code4 = code[4];
	code4["stage"] = 3;
	code4[0] = [];
	code4[0].append([0,1]);
	code4[0].append([2,3]);
	code4[1] = [];
	code4[1].append([1,3]);
	code4[1].append([0,2]);
	code4[2] = [];
	code4[2].append([1,2]);





def printpreamble(ways):
	print """\
import FIFO::*;
import FIFOF::*;
import Clocks::*;
import Vector::*;
	
import SortingNetwork::*;
	
module mkSortingNetwork"""+str(ways)+"""#(Bool descending) (SortingNetworkIfc#(inType, """+str(ways)+"""))
	provisos(
	Bits#(Vector::Vector#("""+str(ways)+""", inType), inVSz),
	Bits#(inType,inTypeSz), Ord#(inType), Add#(1,a__,inTypeSz)
	);

"""

def printfooter():
	print """\

endmodule
"""

def main(ways):
	if not ways in code:
		print "ERROR! "+str(ways)+" not in database"
		return;
	codecur = code[ways];
	stage = codecur["stage"];

	print """\
	Vector#("""+str(ways)+""", FIFO#(inType)) st0Q <- replicateM(mkFIFO);

"""
	#Vector#(ways, FIFO#(inType)) st"""+str(stage)+"""Q <- replicateM(mkFIFO);
	stagesrc = [];
	for i in xrange(ways):
		stagesrc.append([True,i]); # skip(fifo), idx. If False (cas) -> False, i, [0,1]
	for s in xrange(stage):
		nstagesrc = [];
		swaps = codecur[s];
		swapc = len(swaps);
		skips = ways-(swapc*2);
		print "	Vector#("+str(swapc)+", OptCompareAndSwapIfc#(inType)) cas"+str(s+1)+" <- replicateM(mkOptCompareAndSwap(descending));";
		if ( skips > 0 ):
			print "	Vector#("+str(skips)+", FIFO#(inType)) st"+str(s+1)+"Q <- replicateM(mkFIFO);";
		print "	rule stage"+str(s)+";"
		for i in xrange(ways):
			if stagesrc[i][0] == True:
				qname = "st"+str(s)+"Q["+str(stagesrc[i][1])+"]";
				print "		let td"+str(i)+ " = "+qname+".first;";
				print "		"+qname+".deq;";
			else:
				casname = "cas"+str(s)+"["+str(stagesrc[i][1])+"]";
				if ( stagesrc[i][2] == 0 ):
					print "		let casd"+str(stagesrc[i][1])+" <- " + casname + ".get;";
					print "		let td"+str(i)+ " = tpl_1(casd"+str(stagesrc[i][1])+");";
				else:
					print "		let td"+str(i)+ " = tpl_2(casd"+str(stagesrc[i][1])+");";


		for i in xrange(ways):
			nstagesrc.append([]);
		for i in xrange(swapc):
			sw = swaps[i];
			casname = "cas"+str(s+1)+"["+str(i)+"]";
			print "		"+casname+".put(tuple2(td"+str(sw[0])+", td"+str(sw[1])+"));";
			nstagesrc[sw[0]] = [False, i, 0];
			nstagesrc[sw[1]] = [False, i, 1];
		
		fifoidx = 0;
		for i in xrange(ways):
			if ( nstagesrc[i] != [] ): continue;
			fifoname = "st"+str(s+1)+"Q["+str(fifoidx)+"]";
			print "		"+fifoname+".enq(td"+str(i)+");";
			nstagesrc[i] = [True,fifoidx];
			fifoidx += 1;
			if ( fifoidx > skips ): print "//ERROR!!";

			
		print "	endrule"
		stagesrc = nstagesrc;


		
		

	print """\
	method Action enq(Vector#("""+str(ways)+""", inType) data);
		for (Integer i = 0; i < """+str(ways)+"""; i=i+1 ) begin
			st0Q[i].enq(data[i]);
		end
	endmethod
	method ActionValue#(Vector#("""+str(ways)+""", inType)) get;
		Vector#("""+str(ways)+""",inType) outd;""";

	s = stage;
	for i in xrange(ways):
		if stagesrc[i][0] == True:
			qname = "st"+str(s)+"Q["+str(stagesrc[i][1])+"]";
			print "		let td"+str(i)+ " = "+qname+".first;";
			print "		"+qname+".deq;";
		else:
			casname = "cas"+str(s)+"["+str(stagesrc[i][1])+"]";
			if ( stagesrc[i][2] == 0 ):
				print "		let casd"+str(stagesrc[i][1])+" <- " + casname + ".get;";
				print "		let td"+str(i)+ " = tpl_1(casd"+str(stagesrc[i][1])+");";
			else:
				print "		let td"+str(i)+ " = tpl_2(casd"+str(stagesrc[i][1])+");";
		print "		outd["+str(i)+"] = td"+str(i)+";";
	print """\
		return outd;
	endmethod
"""

populatecode();

printpreamble(8);
main(8)
printfooter();

printpreamble(4);
main(4)

