#include "test_card.h"
#include <cassert>
#include <cstdio>
#include <initializer_list>
void send(TestCard &c, std::initializer_list<uint8_t> s){for(auto b:s)c.write(b);}
uint8_t get(TestCard &c){uint8_t b=0;assert(c.read(b));return b;}
int main(){
 TestCard c;
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x7f,0x20});assert(get(c)==0x9f&&get(c)==0x16&&c.selected()==0x7f20);
 send(c,{0xa0,0xf2,0,0,15});assert(get(c)==0xf2);uint8_t d[15];for(auto &b:d)b=get(c);assert(d[4]==0x7f&&d[5]==0x20&&d[6]==2&&d[13]==0xb0);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xf2,0,0,22});assert(get(c)==0xf2);uint8_t full[22];for(auto &b:full)b=get(c);assert(full[12]==9&&full[13]==0xb0&&full[18]==0x83&&full[21]==0x8a);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0xb7});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xc0,0,0,15});assert(get(c)==0xc0);for(auto &b:d)b=get(c);assert(d[3]==3&&d[4]==0x6f&&d[5]==0xb7&&d[6]==4&&d[13]==0);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xf2,0,0,15});assert(get(c)==0xf2);for(auto &b:d)b=get(c);assert(d[4]==0x7f&&d[5]==0x20&&d[6]==2);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xb0,0,0,3});assert(get(c)==0xb0&&get(c)==0x11&&get(c)==0xf2&&get(c)==0xff&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,5});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xc0,0,0,15});assert(get(c)==0xc0);for(auto &b:d)b=get(c);assert(d[3]==1&&d[5]==5);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xb0,0,0,1});assert(get(c)==0xb0&&get(c)==1&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0xae});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,1});assert(get(c)==0xb0&&get(c)==3&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0x38});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xc0,0,0,15});assert(get(c)==0xc0);for(auto &b:d)b=get(c);assert(d[3]==16&&d[5]==0x38);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xb0,0,0,16});assert(get(c)==0xb0);for(int i=0;i<16;i++)assert(get(c)==0);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0x7e});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,11});assert(get(c)==0xb0);for(int i=0;i<10;i++)assert(get(c)==0xff);assert(get(c)==1&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0xad});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,4});assert(get(c)==0xb0&&get(c)==0&&get(c)==0&&get(c)==0&&get(c)==2&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,7});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,9});assert(get(c)==0xb0&&get(c)==8&&get(c)==9);for(int i=0;i<7;i++)get(c);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x6f,0x78});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,2});assert(get(c)==0xb0&&get(c)==0&&get(c)==1&&get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x3f,0});assert(get(c)==0x9f&&get(c)==0x16);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0x2f,0xe2});assert(get(c)==0x9f&&get(c)==0x0f);
 send(c,{0xa0,0xb0,0,0,10});assert(get(c)==0xb0);int digits[20],n=0;for(int i=0;i<10;i++){auto b=get(c);digits[n++]=b&15;if((b>>4)!=15)digits[n++]=b>>4;}int sum=0;for(int i=0;i<n;i++){int v=digits[i];assert(v<10);if((n-i)%2==0){v*=2;if(v>9)v-=9;}sum+=v;}assert(n==19&&sum%10==0);assert(get(c)==0x90&&get(c)==0);
 send(c,{0xa0,0xa4,0,0,2});assert(get(c)==0xa4);send(c,{0xff,0xff});assert(get(c)==0x94&&get(c)==4&&c.selected()==0x2fe2);
 send(c,{0xa0,0xa4,0}); auto saved=c.save(); TestCard resumed; assert(resumed.restore(saved)); send(resumed,{0,2}); assert(get(resumed)==0xa4); send(resumed,{0x7f,0x20}); assert(get(resumed)==0x9f && get(resumed)==0x16);
 c.reset();send(c,{0xa0,0x10,0,0,3});assert(get(c)==0x10);send(c,{1});auto profile=c.save();TestCard after;assert(after.restore(profile));send(after,{2,3});assert(get(after)==0x90&&get(after)==0);
 c.reset();assert(c.selected()==0x3f00);uint8_t x;assert(!c.read(x));std::puts("PASS: diagnostic GSM T=0 SELECT, STATUS, ICCID and errors");
}
