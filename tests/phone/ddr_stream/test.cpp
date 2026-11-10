#include "Vngage_ddr_stream.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <cstring>
#include <vector>

struct Write { uint32_t addr; uint64_t data; uint8_t be; };
struct Test {
    Vngage_ddr_stream d;
    std::array<uint8_t,16384> memory{}, reference{};
    std::deque<Write> writes;
    std::vector<uint64_t> expected;
    uint32_t rng=0x7351b9a3, cycles=0, descriptors=0, read_commands=0, write_commands=0, returned=0;
    unsigned pending=0, physical_index=0, base=0, total=0, consumed=0, owner=0;
    unsigned oracle_address=0,oracle_count=0;bool oracle_read_pending=false,oracle_write=false,delivery_cancelled=false;
    int first_physical=-1,last_physical=-1,first_offer=-1,first_consume=-1,last_consume=-1;
    unsigned simultaneous=0,max_occupancy=0;
    bool completion_seen=false,completion_error=false,completion_cancel=false;
    int force_busy=-1, force_data=-1, force_client=-1;
    bool issue_edge=false, held=false, accepted=false, active_cancel=true, read_held=false;
    uint64_t held_read_data=0;unsigned held_read_owner=0;bool held_read_last=false;
    uint32_t held_addr=0; uint64_t held_data=0; unsigned held_be=0,held_burst=0,held_op=0;
    uint32_t random() { rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng; }
    void check(bool ok,const char *msg) { if(!ok){std::fprintf(stderr,"FAIL cycle%u: %s state idle%d pending%u consumed%u\n",cycles,msg,d.idle,pending,consumed); std::exit(1);} }
    uint64_t word(const std::array<uint8_t,16384>& a,unsigned at) { uint64_t v=0; for(unsigned j=0;j<8;j++)v|=uint64_t(a[(at+j)%a.size()])<<(j*8); return v; }
    Test() {
        for(unsigned j=0;j<memory.size();j++)memory[j]=reference[j]=uint8_t((j*43)^(j>>7)^0xc5);
        d.clk=0; d.req_valid=0;d.write_valid=0;d.read_ready=0;d.phone_reset=0;d.transport_reset=1;
        step();step();d.transport_reset=0;
    }
    void step() {
        ++cycles;check(cycles<2000000,"global timeout");
        if(d.transport_reset||(d.phone_reset&&active_cancel))delivery_cancelled=true;
        d.clk=0; d.ddr_busy=force_busy<0 ? ((random()%5)<2) : force_busy;
        d.read_ready=force_client<0 ? ((random()%4)!=0) : force_client;
        d.ddr_dout_ready=0;d.ddr_dout=0;d.eval();
        bool new_read=d.ddr_rd&&!d.ddr_busy;
        if(held)check(d.ddr_addr==held_addr&&d.ddr_din==held_data&&d.ddr_be==held_be&&d.ddr_burstcount==held_burst&&((d.ddr_rd?1u:0u)|(d.ddr_we?2u:0u))==held_op,"busy-held physical command changed, including across reset");
        if(new_read){
            check(!pending,"more than one physical read outstanding");
            check(oracle_read_pending,"unexpected/duplicate physical read command");
            check(d.ddr_addr*8==oracle_address&&d.ddr_burstcount==oracle_count,"physical read address/count differs from accepted descriptor");
            oracle_read_pending=false;
            base=d.ddr_addr*8;total=d.ddr_burstcount;physical_index=0;pending=total;consumed=0;
            check(total>=1&&total<=64,"invalid physical count");expected.clear();
            for(unsigned i=0;i<total;i++)expected.push_back(word(reference,oracle_address+i*8));
            read_commands++;
        }
        bool emit=pending && ((new_read&&issue_edge)||(!new_read&&(force_data<0 ? random()%3!=0:force_data)));
        if(emit){
            if(first_physical<0)first_physical=cycles;
            last_physical=cycles;
            d.ddr_dout_ready=1;d.ddr_dout=word(memory,base+physical_index*8);}
        d.eval();
        if(d.read_valid){
            check(!delivery_cancelled,"logical prefix escaped after cancellation");
            if(first_offer<0)first_offer=cycles;
        }
        if(read_held && !d.transport_reset && !(d.phone_reset && active_cancel))
            check(d.read_valid && d.read_data==held_read_data && d.read_owner==held_read_owner && bool(d.read_last)==held_read_last,"logical payload changed under response backpressure");
        read_held=d.read_valid&&!d.read_ready;
        held_read_data=d.read_data;held_read_owner=d.read_owner;held_read_last=d.read_last;
        if(d.read_valid&&d.read_ready){
            check(!d.transport_reset&&(!d.phone_reset||!active_cancel),"cancelled transaction emitted a beat");
            check(consumed<expected.size(),"extra logical response beat");
            check(d.read_owner==owner,"live/incorrect response owner");
            check(d.read_data==expected[consumed],"byte scoreboard read mismatch or BRAM prefetch error");
            check(bool(d.read_last)==(consumed+1==total),"incorrect logical last");
            if(first_consume<0)first_consume=cycles;
            last_consume=cycles;
            if(emit)simultaneous++;
            consumed++;returned++;
        }
        if(d.ddr_we&&!d.ddr_busy){
            check(d.ddr_burstcount==1,"assumed unsupported physical write burst");
            check(!writes.empty(),"unexpected or repeated physical write");
            Write w=writes.front();writes.pop_front();
            check(d.ddr_addr*8==w.addr&&d.ddr_din==w.data&&d.ddr_be==w.be,"physical write address/data/lane mask mismatch");
            for(unsigned j=0;j<8;j++){
                if(d.ddr_be&(1u<<j))memory[(d.ddr_addr*8+j)%memory.size()]=d.ddr_din>>(j*8);
                if(w.be&(1u<<j))reference[(w.addr+j)%reference.size()]=w.data>>(j*8);
            }
            check(memory==reference,"ordered byte memory mismatch");write_commands++;
        }
        accepted=d.req_valid&&d.req_ready;
        held=(d.ddr_rd||d.ddr_we)&&d.ddr_busy;
        held_addr=d.ddr_addr;held_data=d.ddr_din;held_be=d.ddr_be;held_burst=d.ddr_burstcount;held_op=(d.ddr_rd?1u:0u)|(d.ddr_we?2u:0u);
        d.clk=1;d.eval();
        if(emit){pending--;physical_index++;}
        if(physical_index>=consumed && physical_index-consumed>max_occupancy)max_occupancy=physical_index-consumed;
        if(d.done&&!oracle_write){
            check(!pending,"read completed before physical tail drained");
            if(!d.error&&!d.cancelled)check(consumed==oracle_count,"read succeeded before final logical consumption");
        }
        if(d.done){
            check(d.done_owner==owner,"completion owner changed after descriptor capture");
            check(!completion_seen,"duplicate descriptor completion");
            completion_seen=true;completion_error=d.error;completion_cancel=d.cancelled;
        }
    }
    void descriptor(bool write,bool stream,uint32_t addr,unsigned count,bool cancel=true,uint64_t data=0,unsigned mask=255) {
        while(!d.req_ready)step(); owner=(descriptors++%4); consumed=0;active_cancel=cancel;
        oracle_address=addr;oracle_count=count;oracle_write=write;delivery_cancelled=false;completion_seen=false;completion_error=false;completion_cancel=false;
        first_physical=last_physical=first_offer=first_consume=last_consume=-1;simultaneous=0;max_occupancy=0;physical_index=0;expected.clear();
        oracle_read_pending=!write&&count>=1&&count<=64&&(addr&7)==0&&uint64_t(addr)+uint64_t(count)*8<=0x100000000ULL&&!(d.phone_reset&&cancel);
        d.req_owner=owner;d.req_cancel_on_phone=cancel;d.req_write=write;d.req_stream=stream;d.req_addr=addr;d.req_count=count;d.req_data=data;d.req_be=mask;d.req_valid=1;
        do step();while(!accepted);
        d.req_valid=0;
        // Poison every live descriptor field after acceptance.
        d.req_owner=owner^3;d.req_addr=0xfffffff8;d.req_count=127;d.req_write=!write;d.req_stream=!stream;d.req_be=0;d.req_data=~data;d.req_cancel_on_phone=!cancel;
    }
    void finish(bool error=false,bool cancel=false) {
        unsigned n=0;while(!completion_seen){step();check(++n<10000,"operation did not finish");}
        check(completion_error==error&&completion_cancel==cancel,"completion status mismatch");
        check(writes.empty(),"missing physical write effects");
        check(!oracle_read_pending,"descriptor read command never issued");
        step();
    }
    void beat(uint64_t data,unsigned mask,bool last) {
        d.write_valid=0;for(unsigned n=random()%4;n;n--)step();
        d.write_data=data;d.write_be=mask;d.write_last=last;d.write_valid=1;
        bool take=false;do {d.clk=0;d.eval();take=d.write_ready;step();}while(!take);
        d.write_valid=0;d.write_data=~data;d.write_be=0;d.write_last=!last;
    }
    void read(unsigned addr,unsigned n) {descriptor(false,false,addr,n);finish();check(consumed==n,"missing logical read beats");}
    void scalar(unsigned addr,uint64_t data,unsigned mask) {writes.push_back({addr,data,uint8_t(mask)});descriptor(true,false,addr,1,true,data,mask);finish();}
    void reset_pulse(bool cold) {if(cold)d.transport_reset=1;else d.phone_reset=1;step();if(cold)d.transport_reset=0;else d.phone_reset=0;}
    void wait_offer(bool write) {unsigned n=0;while(!(write?d.ddr_we:d.ddr_rd)){step();check(++n<100,"no physical offer");}}
    void metrics(const char* name,unsigned n,bool baseline) {
        std::printf("METRIC mode=%s case=%s count=%u first_offer=%d first_consume=%d final_physical=%d final_consume=%d simultaneous=%u max_buffered=%u\n",
            baseline?"fullbuffer":"overlap",name,n,first_offer-first_physical,first_consume-first_physical,
            last_physical-first_physical,last_consume-first_physical,simultaneous,max_occupancy);
    }
    void overlap(bool baseline) {
        force_busy=0;force_client=1;issue_edge=true;
        for(unsigned n:{4u,64u})for(bool delayed:{false,true}) {
            force_data=delayed?0:1;
            descriptor(false,false,504,n);step();check(first_physical>=0,"missing earliest physical response");
            if(delayed) {
                for(unsigned i=0;i<20;i++)step();
                if(baseline)check(consumed==0,"baseline unexpectedly delivered prefix");
                else check(consumed==1 && first_offer<0x7fffffff,"first beat waited for delayed physical tail");
                check(pending==n-1,"delayed tail schedule changed");
                force_data=1;
            }
            finish();check(consumed==n,"latency test missing beats");metrics(delayed?"delayed-tail":"continuous",n,baseline);
            if(!baseline){
                check(first_offer-first_physical==1&&first_consume-first_physical==1,"first registered beat was not promptly available");
                check(first_offer<last_physical,"first logical beat waited for complete burst");
                if(!delayed)check(last_consume-first_consume==int(n)-1&&simultaneous==n-1,"continuous stream did not sustain one beat per cycle");
            }
        }
        if(baseline){std::puts("PASS D1 full-buffer latency baseline");return;}
        // Stall before first beat, absorb every physical beat, then drain at
        // one beat/clock. Forwarded first head must match BRAM after mux change.
        force_data=1;force_client=0;descriptor(false,false,1024,64);step();while(pending)step();
        for(unsigned i=0;i<8;i++)step();check(consumed==0&&max_occupancy==64,"full reserved capacity was not retained");
        force_client=1;finish();check(consumed==64&&last_consume-first_consume==63,"full queue did not drain continuously");metrics("full-stall-drain",64,false);
        // Simultaneous capture/consume, middle stall, catch-up to empty, then
        // repeated empty->nonempty forwarding with deliberately gapped DDR.
        force_data=1;force_client=1;descriptor(false,false,2048,16);step();step();
        force_client=0;for(unsigned i=0;i<3;i++)step();
        force_data=0;force_client=1;while(consumed<physical_index)step();step();check(!d.read_valid,"empty queue retained valid");
        while(pending){force_data=1;step();force_data=0;for(unsigned i=0;i<3;i++)step();}
        finish();check(consumed==16,"catch-up/gap test missing bytes");metrics("mid-stall-catchup-gaps",16,false);
        // Delivered prefixes are provisional. A short reset pulse suppresses
        // all further logical beats while the rest of the physical burst drains.
        for(bool cold:{false,true}) {
            force_data=0;force_client=1;descriptor(false,false,3072,64);step();step();
            check(consumed==1&&pending==63,"prefix cancellation not in-flight");
            reset_pulse(cold);force_data=1;finish(false,true);
            check(consumed==1&&!pending,"cancel leaked logical tail or skipped physical drain");
            force_data=1;read(4096,4);check(consumed==4,"stale bytes/tag after prefix cancellation");
        }
        std::puts("PASS D1 overlap: delayed4/64 tails, one registered first-beat cycle, one beat/clock continuous, full64 stall, catch-up collisions/gaps, provisional-prefix cancellation and fresh owner");
    }
    void run() {
        // Every scalar lane mask, including no-op, and descriptor poisoning.
        for(unsigned mask=0;mask<256;mask++)scalar((mask%64)*8,0x1234bcde00000000ULL^(uint64_t(mask)*0x9e37),mask);
        issue_edge=true;read(0,1);read(24,4);read(504,64);read(15872,64);issue_edge=false;
        for(unsigned n=0;n<180;n++)read((random()%1900)*8,1+random()%64);
        // Streaming restore preserves exact per-beat masks/data and boundaries.
        for(unsigned n:{1u,4u,64u}){
            std::vector<Write> v;for(unsigned i=0;i<n;i++)v.push_back({504+i*8,0xfedcba9876543210ULL^(uint64_t(i)<<33),uint8_t(random())});
            for(auto w:v)writes.push_back(w);descriptor(true,true,504,n);
            for(unsigned i=0;i<n;i++)beat(v[i].data,v[i].be,i+1==n);finish();read(504,n);
        }
        // Synthesizable invalid descriptor rejection, no DDR issue.
        for(auto c:{0u,65u,127u}){descriptor(false,false,0,c);finish(true);}
        descriptor(false,false,1,1);finish(true);descriptor(false,false,0xfffffff8,2);finish(true);
        descriptor(true,false,0,4);finish(true);
        // Wrong stream last rejects the offending beat; committed prefix survives.
        descriptor(true,true,1024,4);writes.push_back({1024,0xaabbccdd,0x5a});beat(0xaabbccdd,0x5a,false);
        while(!d.write_ready)step();beat(0xdeadbeef,255,true);finish(true);read(1024,4);
        // Both reset domains at every read phase, including stable busy-held
        // command, accepted/read-wait, prefetch and stalled response delivery.
        for(bool cold:{false,true})for(unsigned phase=0;phase<4;phase++){
            force_busy=phase==0?1:0;force_data=0;force_client=0;
            descriptor(false,false,1536,4);wait_offer(false);
            if(phase!=0){step();check(pending==4,"read command was not accepted");}
            if(phase>=2){force_data=1;while(pending)step();if(phase==3)step();}
            reset_pulse(cold);force_busy=0;force_data=1;force_client=1;finish(false,true);
            check(!pending,"reset returned before physical read drained");
            force_busy=-1;force_data=-1;force_client=-1;read(2048,4);
        }
        // Reset while WRITE_NEED issues nothing; busy-held current beat must
        // still commit exactly once, then report canceled instead of success.
        for(bool cold:{false,true}){
            descriptor(true,true,2560,4);reset_pulse(cold);finish(false,true);
            force_busy=1;writes.push_back({2560,0x8877665544332211ULL,0x35});
            descriptor(true,true,2560,4);beat(0x8877665544332211ULL,0x35,false);wait_offer(true);
            reset_pulse(cold);force_busy=0;finish(false,true);force_busy=-1;read(2560,4);
        }
        // Cancel before any physical offer, and after a committed stream prefix.
        d.phone_reset=1;descriptor(false,false,3072,1,true);finish(false,true);d.phone_reset=0;
        descriptor(true,true,2816,4);writes.push_back({2816,0x1122334455667788ULL,255});beat(0x1122334455667788ULL,255,false);
        while(!d.write_ready)step();reset_pulse(false);finish(false,true);read(2816,4);
        descriptor(true,true,2816,1);beat(0,255,false);finish(true);
        // Non-cancellable loader transfers remain functional while phone held.
        d.phone_reset=1;writes.push_back({3072,0x13579bdf2468ace0ULL,255});
        descriptor(true,false,3072,1,false,0x13579bdf2468ace0ULL,255);finish();
        descriptor(false,false,3072,1,false);finish();d.phone_reset=0;check(consumed==1,"loader readback failed");
        // Reset coincident with earliest response on the accepted command edge.
        force_busy=1;issue_edge=true;descriptor(false,false,4096,1);wait_offer(false);
        d.transport_reset=1;force_busy=0;finish(false,true);d.transport_reset=0;issue_edge=false;
        check(memory==reference,"final byte image mismatch");
        std::printf("PASS D1 stream byte scoreboard: %u descriptors, %u DDR reads, %u masked writes, %u returned beats, %u clocks; all masks, boundaries, backpressure, owner poison, invalid/partial/reset/loader cases\n",descriptors,read_commands,write_commands,returned,cycles);
    }
};
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Test t;
    if(argc>1&&std::strcmp(argv[1],"--overlap")==0)t.overlap(false);
    else if(argc>1&&std::strcmp(argv[1],"--fullbuffer-baseline")==0)t.overlap(true);
    else t.run();
    return 0;
}
