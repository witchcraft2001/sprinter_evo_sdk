#ifndef __STRUCTS
#define __STRUCTS
static u8 spritenums[64];

typedef struct pl
{
	u8 x;
	u8 y;
	u8 damaged;
	i16 health; //жизни
	u8 speed;//скорость
	u8 old_speed;
	u8 anim_frame;
	u8 tanim_frame; //16 times
	i16 coins; //монеты
	u16 pwr;   //сила
	u16 old_pwr;
	u8 shoot_spd; //задержка
	u8 old_shoot_spd;
	u16 bullifetime; //жизнь пули
	u16 old_bullifetime;
	u8 shoot_delay; 
	u8 bulspeed; //cкорость пули
	u8 bonuses[4];
} Player;
typedef struct bl
{
	u8 x;
	u8 y;
	i8 dx;
	i8 dy;
	u8 pl;
	u8 power;
	u8 sprnum;
	u16 picnum;
	u16 life;

	u8 isfree;
}Bullet;
typedef struct type_enem
{
	u8 health;
	u8 move_type;
	u8 shoot_type;
	u8 power;
	u8 shoot_delay;
	u8 speed;
	u8 move_delay;
	u16 picnum;
	u8 numinmas;
	u16 bullifetime;
	u8 bulspeed;
} Type_enemy;
typedef struct enem
{
	u8 x;
	u8 y;
	u8 dx;
	u8 dy;
	i16 health;
	u16 sprnum;
	u8 type;
	u8 dead;
	u16 picnum;
	u8 shoot_delay;
	u8 movdelay;
	u8 animframe;
	u8 animdelay;
	u8 coin;
	u8 type_bonus;
	u8 lnapr;
} Enemy;


u8 find_free_sprite()
{
	static u8 a;
	for(a=1;a<64;a++)
	{
		if (spritenums[a]==0)
		{
			//spritenums[a]=1;
			return a;
		}
		
	}
	return 128;
}
u8 find_free_sprite_bul()
{
	static u8 a;
	for(a=1;a<64;a++)
	{
		if (spritenums[a]==0)
		{
			//spritenums[a]=1;
			return a;
		}
		
	}
	return 128;
}
#endif