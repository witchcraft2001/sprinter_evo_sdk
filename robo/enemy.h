#ifndef __ENEMY
#define __ENEMY
//#include <stdlib.h>
#include "structs.h"
#include "dif_tables.h"
#define noattackcount 5
#define followattackcount 5
#define diagonalattackcount 6
#define lineattackcount 6

static Type_enemy types_enemy[4];
static Enemy enemys[16];

static u8 count_enemys;
static u8 curlevel=1;

static i16 boss_health;
static u8 boss_cur_shot_type;
static u8 boss_shoot_delay;
static u8 boss_cur_shoot_delay;

static u8 noattack_m[]={0,1,0,0,0};
static u8 followattack_m[]={0,0,1,1,1};
static u8 diagonalattack_m[]={0,0,1,0,0,1};
static u8 lineattack_m[]={1,0,1,0,1,1};

static u16 noattack[]={12,27,44,105,306};
static u16 followattack[]={9,21,70,137,108};
static u16 diagonalattack[]={6,24,50,73,56,271};
static u16 lineattack[]={15,18,53,76,88,326};
u8 gn_napr(i8 dx,i8 dy)
{
	if(dx==0&&dy>0) return 0;
	if(dx<0&&dy>0) return 1;
	if(dx<0&&dy==0) return 2;
	if(dx<0&&dy<0) return 3;
	if(dx==0&&dy<0) return 4;
	if(dx>0&&dy<0) return 5;
	if(dx>0&&dy==0) return 6;
	if(dx>0&&dy>0) return 7;
	return 128;
}
void gen_types_enemy(i16 points)
{

/*
	типы перемещения
	0 стоять на месте. стоимость 0
	1 преследовать через все. стоимость 40
	2 преследовать только по полу. стоимость 30
	
	атака
	0 не стрелять. стоимость 0
	1 стрелять в направлении игрока. стоимость 20
	2 стрелять по диагоналям. стоимость 30
	3 стрелять по горизонталям. стоимость 30
	
	скорость перемещения
	изначально 1
	стоимость увеличения 15 на единицу
	максимум 8
	
	задержка перемещения
	изначально 10
	стоимость увеличения 15 на единицу
	максимум 0
	
	сила атаки
	изначально 1
	стоимость увеличения 15 на еиницу
	максимум 255
	
	задержка стрельбы
	изначально 120
	стоимость увеличения 5 на 10 штук
	максимум 30
	
	скорость полета пули
	изначально 1
	стоимость улучшения 100 на единицу
	максимум 4
	
	время жизни пули
	изначально 10
	стоимость улучшения 5 на 5 штук
	максимум 90
	
	количество жизни
	изначально 10
	стоимость улучшения 2 на 5 штук
	максимум 255
*/
	static i16 a,c,d,curpoints;
	static u8 b;

	for(a=0;a<4;a++)
	{
		types_enemy[a].health=10;
		types_enemy[a].power=5;
		types_enemy[a].shoot_delay=120;
		types_enemy[a].speed=1;
		types_enemy[a].move_delay=10;
		types_enemy[a].bullifetime=15;
		types_enemy[a].bulspeed=1;
		
		//тип перемещения
		curpoints=points;
		if(curpoints>1024)curpoints=1024;
		b=rand16()%3;
		types_enemy[a].move_type=b;
		if(b==1)curpoints-=40;
		if(b==2)curpoints-=30;
		//тип атаки
		
		b=rand16()%32;
		b>>=3;
		if(b==4)b=0;
		types_enemy[a].shoot_type=b;
		if(types_enemy[a].move_type==0&&types_enemy[a].shoot_type==0)types_enemy[a].shoot_type++;
		if(b==1)curpoints-=20;
		if(b==2||b==3)curpoints-=30;
		//-----------------------------------внешний вид
		if(types_enemy[a].shoot_type==0)
		{
			c=1+curlevel+curdif;
			if(c>noattackcount)c=noattackcount;
			b=rand16()%c;
			
			types_enemy[a].picnum=noattack[b];
			types_enemy[a].numinmas=noattack_m[b];
		}
		else if(types_enemy[a].shoot_type==1)
		{
			c=1+curlevel+curdif;
			if(c>followattackcount)c=followattackcount;
			b=rand16()%c;
			types_enemy[a].picnum=followattack[b];
			types_enemy[a].numinmas=followattack_m[b];
		}
		else if(types_enemy[a].shoot_type==2)
		{
			c=1+curlevel+curdif;
			if(c>diagonalattackcount)c=diagonalattackcount;
			b=rand16()%c;
			types_enemy[a].picnum=diagonalattack[b];
			types_enemy[a].numinmas=diagonalattack_m[b];
		}
		else if(types_enemy[a].shoot_type==3)
		{
			c=1+curlevel+curdif;
			if(c>lineattackcount)c=lineattackcount;
			b=rand16()%c;
			types_enemy[a].picnum=lineattack[b];
			types_enemy[a].numinmas=lineattack_m[b];
		}
		
		//-----------------------------------
		c=0;
		
		while(c<8&&curpoints>0)
		{
			c++;
			d=rand16()%7;
			if(d==0)//скорость
			{
				if(types_enemy[a].move_type!=0&&types_enemy[a].speed<8)
				{
					if(curpoints>15)
					{
						curpoints-=15;
						types_enemy[a].speed++;
						c=0;
					}
				}
				else d++;
			}
			else if(d==1)//задержка перемещения
			{
				if(types_enemy[a].move_type!=0&&types_enemy[a].move_delay>0)
				{
					if(curpoints>15)
					{
						curpoints-=15;
						types_enemy[a].move_delay--;
						c=0;
					}
				}
				else d++;
			}
			else if(d==2)//сила атаки
			{
				if(curpoints>10&&types_enemy[a].power<100)
				{
					curpoints-=10;
					types_enemy[a].power+=1;
					c=0;
				}
				else d++;
			}
			else if(d==3)//задержка стрельбы
			{
				if(curpoints>=15&&types_enemy[a].shoot_delay>20)
				{
					curpoints-=15;
					types_enemy[a].shoot_delay-=20;
					//types_enemy[a].shoot_delay=16;
					c=0;
				}
				else d++;
			}
			else if(d==4)//скорость полета пули
			{
				if(curpoints>50&&types_enemy[a].bulspeed<4)
				{
					curpoints-=50;
					types_enemy[a].bulspeed++;
					c=0;
				}
				else d++;
			}
			else if(d==5)//время жизни пули
			{
				if(curpoints>5&&types_enemy[a].bullifetime<90)
				{
					curpoints-=5;
					types_enemy[a].bullifetime+=5;
					c=0;
				}
			}
			else if(d==6)//жизни
			{
				if(curpoints>2&&types_enemy[a].health<250)
				{
					curpoints-=2;
					types_enemy[a].health+=5;
					c=0;
				}
				//else c=0;
			}
			if(curpoints<=5)c=64;
		}
		
		//types_enemy[a].shoot_delay=0;
	}
	
	
}
#endif