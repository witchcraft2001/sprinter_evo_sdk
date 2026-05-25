#ifndef __TEXT
#define __TEXT
static u8 output_x;
static u8 output_y;
static u8 save_output_x;
u8 code_to_char[]={' ','z','x','c','v','a','s','d','f','g','q','w','e','r','t','1','2','3','4','5','0','9','8','7','6','p','o','i','u','y',' ','l','k','j','h',' ',' ','m','n','b'};
//u8 code_to_char[]={ ,32,32,90,88,67,86,65,83,68,70,81,87,69,82,84,49,50,51,52,53,48,57,56,55,54,80,79,73,85,89,76,75,74,72,32,32,77,78,66};
u8 *passwords[]={"gorgo","teseu","venus","minot","apolo","ariad"};

u8 pcharmask=0;
void put_char(u8 n)
{
 if(n>=' ')
{
		if(pcharmask==0)draw_tile(output_x,output_y,n-' ');
		else draw_tile_key(output_x,output_y,n-' ');
}

  ++output_x;

  if(output_x==39||n=='\n')
  {
    output_x=save_output_x;
    
    ++output_y;
    
    if(output_y==24) output_y=1;
  }
}
void put_str(u8* str)
{

  static u8 i;
  select_image(IMG_FONT);
  save_output_x=output_x;
  while(1)
  {
    i=*str++;

    if(!i) break;

    put_char(i);
  }
}
void atoi(u16 i,u8 *str)
{
	static i16 i1,a,c;
	static i16 b;
	static u8 buf[32];
	a=0;
	for(a=0;a<3;a++)
	{
		buf[a]=0;
	}
	do
	{
		i1=i%10;
		i=i/10;
		buf[a]=i1+48;
		a++;
	}while(i!=0);
	c=0;
	if(a==2&&buf[a]==0)
	{
		buf[a]=48;
		a++;
	}
	for(b=a-1;b>=0;b--)
	{
		
		str[c]=buf[b];
		c++;
	}
	str[c]='\0';
}

unsigned int lsqrt(unsigned long arg){
static char count=16;
static unsigned long res=0,tmp=0;
	if(arg!=0){ 
		if(!(arg&0xFF000000)){arg<<=8;count-=4;}


		res=1;
		while((tmp<1)&&(count)){
			count--;
			if(arg&0x80000000UL)tmp|=2;
			if(arg&0x40000000UL)tmp|=1;

			arg<<=2;


		};//поиск первой 1-ы
		tmp--;
		for(count;count;count--){
			tmp<<=2;
			res<<=1;

			if(arg&0x80000000UL)tmp|=2;
			if(arg&0x40000000UL)tmp|=1;
			arg<<=2;

			if( tmp>=((res<<1)|1)){
				tmp-=((res<<1)|1);
				res|=1;
			}
			
		}
	}
	return (unsigned int)res;
}
#endif