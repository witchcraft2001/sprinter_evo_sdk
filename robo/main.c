#include <evo.h>

#include "structs.h"
#include "map.h"
#include "enemy.h"
#include "text.h"
#include "dif_tables.h"
#define pathrecalc 60
#define def_bonus_variant 10

u8 keys[255];
u8 currecalc,opened;
u8 count_rooms;
i8 pdx,pdy;
u8 ingame,pldead;
u8 dmg_played=0;
u8 bonus_variant;
i8 bbdx[8]={0,8,12,8,0,-8,-12,-8};
i8 bbdy[8]={-20,-12,0,12,20,12,0,-12};
u16 monpause=0;
void wait_a_key()
{
	u8 a,b;
	a=1;
	while(a)
	{
		keyboard(keys);
		for(b=0;b<255;b++)
		{
			if(keys[b]==KEY_DOWN)a=0;
			
		}
	}
	for(a=0;a<255;a++)keys[a]=0;
}
u8 check_a_key()
{
	u8 a,b;
	a=1;

	keyboard(keys);
	for(b=0;b<255;b++)
	{
			if(keys[b]==KEY_DOWN)a=0;
			
	}
	//for(a=0;a<255;a++)keys[a]=0;
	return a;
}
void show_instructions()
{	
	u8 a,b;
	sprites_stop();
	clear_screen(4);
	swap_screen();
	clear_screen(4);
	swap_screen();
	output_x=0;
	output_y=0;
	//put_str("Cтранички перелистывыются любой кнопкой                                       Эта игра задумывалась, как наш ответ   binding of isaac, но в процессе разраб-отки получилось то, что получилось.    УПРАВЛЕНИЕ.                            Двигаемся шутерной комбинацией WASD    Стреляем стрелочками (можно и по диаго-нали). Используем бонусы цифровыми     кнопками от 1 до 4 (про них позже).    Клавиша ENTER ставит игру на паузу, а  так же выводит на экран карту этажа и  состояние нашего робота. Повторное     нажатие на enter вернет нас назад в    игру. По окончании уровня мы попадаем  в магазин. В нем все просто: стрелки   вверх и вниз переключают пункт меню    enter- купить улучшение (если хватает  монет и мы не достигли максимума).     Кнопка q-выход из магазина на следующийэтаж.");
    put_str("Cтранички перелистывыются любой кнопкой                                       Эта игра задумывалась, как наш ответ   binding of isaac, но в процессе разраб-отки получилось то, что получилось.                                           УПРАВЛЕНИЕ.                            Двигаемся шутерной комбинацией WASD    треляем стрелочками (можно и по диаго- нали).                                 Кнопки 9/0 это вкл/выкл звуков и музыкиИспользуем бонусы цифровыми кнопками   от 1 до 4 (про них позже).    Клавиша  ENTER ставит игру на паузу, а  так же  выводит на экран карту этажа и         состояние нашего робота. Повторное     нажатие на enter вернет нас назад в    игру. По окончании уровня мы попадаем  в магазин. В нем все просто: стрелки   вверх и вниз переключают пункт меню    enter- купить улучшение (если хватает  монет и мы не достигли максимума).     Кнопка q-выход из магазина на следующийэтаж.");
	swap_screen();
	wait_a_key();
	clear_screen(4);
	output_x=0;
	output_y=0;
	//put_str("О собираемом.                          от убитых монстров остаются либо       монетки, либо с небольшой вероятнстью  бонусы. Бонусов всего 10 видов:                                               1-Сильная атака в 8 сторон             2-Сильная атака вдоль осей             3-Сильная атака по диагоналям          4-Ускорение игрока                     5-Усиление игрока                      6-Увеличение дальности атаки           7-Увеличение скорострельности          8-Восстановление 10ед. жизни           9-Восстановление 20ед. жизни           10-Бонус с вопросиком ;)                                                      Все усиливающие бонусы действуют пока  игрок не выйдет из комнаты. Стреляющие просто однократно выстреливают, а      лечащие и увеличивающие удачу бонусы   просто поднимают нужную характеристику.");
	put_str("О собираемом.                          от убитых монстров остаются либо       монетки, либо с небольшой вероятнстью  бонусы. Бонусов всего 10 видов:                                               1-Сильная атака в 8 сторон             2-Сильная атака вдоль осей             3-Сильная атака по диагоналям          4-Ускорение игрока                     5-Усиление игрока                      6-Увеличение дальности атаки           7-Увеличение скорострельности          8-Восстановление 10ед. жизни           9-Восстановление 20ед. жизни           10-Минное заграждение                  11-Временная заморозка всех монстров   12-Бонус с вопросиком ;)                                                      Все усиливающие бонусы действуют пока  игрок не выйдет из комнаты. Стреляющие просто однократно выстреливают, а      лечащие и увеличивающие удачу бонусы   просто поднимают нужную характеристику.");

	swap_screen();
	wait_a_key();
	output_x=0;
	output_y=0;
	clear_screen(4);
	output_x=17;
	output_y=0;
	put_str("МОНСТРЫ");
	select_image(IMG_SPRITES);
	pal_select(PAL_TILES);
	for(a=0;a<noattackcount;a++)
	{
		print_tile(a*2+16,4,noattack[a]+1,2,64,0);
	}
	output_x=0;
	output_y=6;
	select_image(IMG_FONT);
	put_str("Эти ребята не стреляют, зато довольно  больно кусаются.");
	select_image(IMG_SPRITES);
	for(a=0;a<followattackcount;a++)
	{
		print_tile(a*2+16,8,followattack[a]+1,2,64,0);
	}
	output_x=0;
	output_y=10;
	select_image(IMG_FONT);
	put_str("Они всегда держат тебя на прицеле.");
	select_image(IMG_SPRITES);
	for(a=0;a<diagonalattackcount;a++)
	{
		print_tile(a*2+16,12,diagonalattack[a]+1,2,64,0);
	}
	output_x=0;
	output_y=14;
	select_image(IMG_FONT);
	put_str("Эти монстры стреляют только по диагоналям");
	select_image(IMG_SPRITES);
	for(a=0;a<lineattackcount;a++)
	{
		print_tile(a*2+16,16,lineattack[a]+1,2,64,0);
	}
	output_x=0;
	output_y=18;
	select_image(IMG_FONT);
	put_str("А эти только по вертикали и горизонтали");
	
	select_image(IMG_SPRITES);
	swap_screen();
	wait_a_key();
	
	pal_select(IMG_MAIN4);
	select_image(IMG_FONT);
	clear_screen(4);
	swap_screen();
	clear_screen(4);
	swap_screen();
	output_x=0;
	output_y=0;
	put_str("Цель этой игры дойти до самого низа    лабиринта и убить главного босса, по   пути прокачавшись как можно сильнее.   Сам лабиринт каждый раз процедурно     генерируется. Меняет свои размеры и    население в зависимости от сложности и глубины. Соответственно чем выше       сложность, тем больше этажей, они шире,на них больше монстров, они толще и    крутеют быстрее, но и монеток из них   выпадает больше, тоесть прокачаться    можно сильнее.                         В общем-то и все. Если будут возникать какие-либо вопросы пишите на           kein1985@yandex.ru                     Или обращайтесь на zx.pk.ru ко мне     Hippiman.                              Приятной игры.");
	swap_screen();
	wait_a_key();
	sprites_start();
}
/*
help text
странички перелистывыются любой кнопкой
эта игра задумывалась, как наш ответ
binding of isaac, но в процессе разраб-
отки получилось то, что получилось.
управление.
двигаемся шутерной комбинацией WASD
стреляем стрелочками (можно и по дивго-
нали). используем бонусы цифровыми
кнопками от 1 до 4 (про них позже).
Клавиша enter ставит игру на паузу, а
так же выводит на экран карту этажа и
состояние нашего робота. повторное
нажатие на enter вернет нас назад в
игру. По окончании уровня мы попадаем
в магазин. В нем все просто: стрелки
вверх и вниз переключают пункт меню
enter- купить улучшение (если хватает
монет и мы не достигли максимума).
кнопка q-выход из магазина на следующий
этаж.
о собираемом.
от убитых монстров остаются либо
монетки, либо с небольшой вероятнстью
бонусы. бонусов всего 10 видов:
1-сильная атака в 8 сторон
2-асильная атака вдоль осей
3-сильная атака по диагоналям
4-ускорение игрока
5-усиление игрока
6-увеличение дальности атаки
7-увеличение скорострельности
8-восстановление 10ед. жизни
9-восстановление 20ед. жизни
10-Увеличение удачливости игрока
                                       
все усиливающие бонусы действуют пока
игрок не выйдет из комнаты. стреляющие
просто однократно выстреливают, а
лечащие и увеличивающие удачу бонусы
просто поднимают нужную характеристику.

                                 
Цель этой игры дойти до самого низа
лабиринта и убить главного босса, по
пути прокачавшись как можно сильнее.
Сам лабиринт каждый раз процедурно
генерируется. Меняет свои размеры и
население в зависимости от сложности и
глубины. Соответственно чем выше
сложность, тем больше этажей, они шире,
на них больше монстров, они толще и
крутеют быстрее, но и монеток из них
выпадает больше, тоесть прокачаться
можно сильнее.
В общем-то и все. Если будут возникать
какие-либо вопросы пишите на
kein1985@yandex.ru                     
Или обращайтесь на zx.pk.ru ко мне
Hippiman.                              
Приятной игры.
*/
void print_pl_health(Player *pl)
{
	u8 buf[6];
	u8 i1,a,c;
	i8 b;
	u8 str[32];
	u8 i;
	a=0;
	output_x=0;
	output_y=0;
	put_char(' ');
	put_char(' ');
	put_char(' ');
	output_x=2;
	output_y=0;
	draw_image(0,0,IMG_HEALTH);
	select_image(IMG_FONT);
	atoi(pl->health,str);
	put_char(str[0]);
	put_char(str[1]);
	put_char(str[2]);
	
	output_x=9;
	output_y=0;
	atoi(pl->coins,str);
	put_char(str[0]);
	put_char(str[1]);
	put_char(str[2]);
	select_image(IMG_TILES);
	for(a=0;a<4;a++)
	{
		if(pl->bonuses[a]!=32)
		{
			
			
			print_tile(a*2,22,12+pl->bonuses[a]*16,2,32,1);
		}
		else print_tile(a*2,22,204,2,32,1);
		print_tile(a*2,22,13+a*16,2,32,1);
	}
	
}
int fastangle(int dx,int dy)
{
	u8 scale;
	int tg,angle;
	scale=8;
					if(dx==0)
					{
						angle = 0;
					}
					else
					{
						tg = (dy << scale) / dx;
						angle = 90 - (45 * tg >> scale);
						if (dx < 0) angle += 180;
					}
					return angle;
}
u8 find_free_bullet()
{
	u8 a;
	for(a=0;a<32;a++)
	{
		if (bullets[a].isfree==1) return a;
	}
	return 64;
}

void move_bullets(Player *pl)
{
	u8 a,b,x,y,x2,y2,xx,yy;
	for (a=0;a<32;a++)
	{

		if(bullets[a].isfree==6)
		{
			bullets[a].isfree=1;
			set_sprite(bullets[a].sprnum,bullets[a].x,bullets[a].y,bullets[a].picnum);
			spritenums[bullets[a].sprnum]=0;
		}
		if(bullets[a].isfree==5)
		{
			bullets[a].picnum=3;
			bullets[a].isfree++;
		}
		if(bullets[a].isfree>=2&&bullets[a].isfree<5)
		{
			bullets[a].isfree++;
		}
		if(bullets[a].isfree!=1)
		{
		
			bullets[a].x+=bullets[a].dx;
			bullets[a].y+=bullets[a].dy;
			if(bullets[a].x<=8||bullets[a].x>=150||bullets[a].y<=8||bullets[a].y>=176)
			{
				bullets[a].picnum=3;
				bullets[a].isfree=6;
				spritenums[bullets[a].sprnum]=0;
				//set_sprite(bullets[a].sprnum,bullets[a].x,bullets[a].y,bullets[a].picnum);
			}
			if(bullets[a].isfree==0)
			{
				bullets[a].life--;
				if(bullets[a].life<=0)
				{
					bullets[a].picnum=3;
					bullets[a].isfree=3;
				}


				x=(bullets[a].x+bullets[a].dx);
				y=(bullets[a].y+bullets[a].dy);
				x=x>>3;
				y=y>>4;
				if(pathfind[x][y]==255&&curmap_tiles[x][y]!=5)
				{
					bullets[a].picnum=3;
					bullets[a].isfree=6;
				}

				if(bullets[a].pl==1)
				{	
					for(b=0;b<16;b++)
					{
						if(enemys[b].dead==0)
						{
							x=bullets[a].x;
							y=bullets[a].y;
							x2=enemys[b].x;
							y2=enemys[b].y;
							if(x+1>=x2&&x+1<x2+8&&y+3>=y2&&y+3<=y2+16)
							{
								if(sndon==1)sfx_play(SFX_ENEMY_DAMAGE,7);
								enemys[b].health-=pl->pwr;
								bullets[a].picnum=rand16()%3*32+67;
								bullets[a].isfree=2;
								
							}
						}
					}
					if(is_final_battle==1)
					{
						if(bullets[a].x>=64&&bullets[a].x<=88&&bullets[a].y>=32&&bullets[a].y<=85)
						{
							if(sndon==1)sfx_play(SFX_BOSS,7);
							boss_health-=pl->pwr;
							//pl->x-=pl->pwr;
							bullets[a].picnum=rand16()%3*32+67;
							bullets[a].isfree=2;
						}
					}
				
				}
			
				else
				{
					x=bullets[a].x;
					y=bullets[a].y;
					x2=pl->x;
					y2=pl->y;
					if(x+1>=x2&&x+1<x2+8&&y+3>=y2&&y+3<=y2+16&&pl->damaged==0)
					{
						pl->damaged=1;
						pl->anim_frame=32;
						pl->health-=bullets[a].power;
						bullets[a].picnum=rand16()%3*32+67;
						bullets[a].isfree=2;
						print_pl_health(pl);
					}
				}
			}
			set_sprite(bullets[a].sprnum,bullets[a].x,bullets[a].y,bullets[a].picnum);


			//pl->x=bullets[a].x;
		}
		//set_sprite(bullets[a].sprnum,bullets[a].x,bullets[a].y,bullets[a].picnum);
		
	}

}
void move_enemys(Player *pl)
{
	u8 a,b,c,bulnum,sprnum,x,y,xx,yy,x2,y2,xx2,yy2;
	i8 buldx,buldy;
	int angle;
	u16 ln,spr;
	liveenemys=0;
	buldx=0;
	buldy=0;
	if(monpause>0)monpause--;
	for(a=0;a<count_enemys;a++)
	{
		if(enemys[a].dead==0)
		{
			liveenemys=1;
			if(monpause==0)
			{
				//-----------------------------------------------------
				if(enemys[a].shoot_delay==0)//shoot
				{
					enemys[a].shoot_delay=1;
					buldx=0;
					buldy=0;
					if (types_enemy[enemys[a].type].shoot_type==2)
					{
						for(b=0;b<4;b++)
						{
							bulnum=find_free_bullet();
		
							if(bulnum!=64)
							{
								sprnum=find_free_sprite_bul();
								if (sprnum!=128)
								{
									buldx=0;
									buldy=0;
									c=types_enemy[enemys[a].type].bulspeed;
									if(b==0)
									{
										buldx=c;
										buldy=-c;
									}
									if(b==1)
									{
										buldx=-c;
										buldy=-c;
									}
									if(b==2)
									{
										buldx=-c;
										buldy=c;
									}
									if(b==3)
									{
										buldx=c;
										buldy=c;
									}
									//if(buldx!=0||buldy!=0)
									//{
									buldy<<=1;
									bullets[bulnum].x=enemys[a].x+3;
									bullets[bulnum].y=enemys[a].y+8;
									bullets[bulnum].dx=buldx;
									bullets[bulnum].dy=buldy;
									bullets[bulnum].isfree=0;
									bullets[bulnum].sprnum=sprnum;
									spritenums[bullets[bulnum].sprnum]=1;
									//bullets[bulnum].picnum=5;
									bullets[bulnum].power=types_enemy[enemys[a].type].power;
									c=bullets[bulnum].power/5;
									c--;
									if(c>9)c=9;
									bullets[bulnum].picnum=c*32+5;
									bullets[bulnum].life=types_enemy[enemys[a].type].bullifetime;
									bullets[bulnum].pl=0;
									//}
								}
							}
						}
						if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
					}
					if (types_enemy[enemys[a].type].shoot_type==3)
					{
					
						for(b=0;b<4;b++)
						{
							bulnum=find_free_bullet();
		
							if(bulnum!=64)
							{
								sprnum=find_free_sprite_bul();
								if (sprnum!=128)
								{
									buldx=0;
									buldy=0;
									c=types_enemy[enemys[a].type].bulspeed;
									if(b==0)
									{
										buldx=0;
										buldy=-c;
									}
									if(b==1)
									{
										buldx=-c;
										buldy=0;
									}
									if(b==2)
									{
										buldx=0;
										buldy=c;
									}
									if(b==3)
									{
										buldx=c;
										buldy=0;
									}
									//if(buldx!=0||buldy!=0)
									//{
										buldy<<=1;
										bullets[bulnum].x=enemys[a].x+3;
										bullets[bulnum].y=enemys[a].y+8;
										bullets[bulnum].dx=buldx;
										bullets[bulnum].dy=buldy;
										bullets[bulnum].isfree=0;
										bullets[bulnum].sprnum=sprnum;
										spritenums[bullets[bulnum].sprnum]=1;
										bullets[bulnum].power=types_enemy[enemys[a].type].power;
										c=bullets[bulnum].power/5;
										c--;
										if(c>9)c=9;
										bullets[bulnum].picnum=c*32+5;
										bullets[bulnum].life=types_enemy[enemys[a].type].bullifetime;
										bullets[bulnum].pl=0;
									//}
								}
							}
						}
						if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
					}
					if (types_enemy[enemys[a].type].shoot_type==1)
					{
						bulnum=find_free_bullet();
						sprnum=find_free_sprite_bul();
						if(bulnum!=64&&sprnum!=128)
						{
							
							buldx=0;
							buldy=0;
							angle=fastangle(enemys[a].x-pl->x,enemys[a].y-pl->y);
							if (angle<0)angle+=360;
							ln=((enemys[a].x-pl->x)<<1)/(enemys[a].y-pl->y);
							c=types_enemy[enemys[a].type].bulspeed;
							if(angle>=22&&angle<67)
							{
								buldx=-c;
								buldy=-c;
							}
							if(angle>=67&&angle<112)
							{
								buldx=-c;
								buldy=0;
							}
							if(angle>=112&&angle<157)
							{
								buldx=-c;
								buldy=c;
							}
							if(angle>=157&&angle<202)
							{
								buldx=0;
								buldy=c;
							}
							if(angle>=202&&angle<247)
							{
								buldx=c;
								buldy=c;
							}
							if(angle>=247&&angle<292)
							{
								buldx=c;
								buldy=0;
							}
							if(angle>=292&&angle<337)
							{
								buldx=c;
								buldy=-c;
							}
							if(ln<1&&(enemys[a].y-pl->y)>0)
							{
								buldx=0;
								buldy=-c;
							}
							if(ln<1&&(enemys[a].y-pl->y)<0)
							{
								buldx=0;
								buldy=c;
							}
							
							if(buldx!=0||buldy!=0)
							{
								buldy<<=1;
								bullets[bulnum].x=enemys[a].x+3;
								bullets[bulnum].y=enemys[a].y+8;
								bullets[bulnum].dx=buldx;
								bullets[bulnum].dy=buldy;
								bullets[bulnum].isfree=0;
								bullets[bulnum].sprnum=sprnum;

								spritenums[bullets[bulnum].sprnum]=1;
								bullets[bulnum].power=types_enemy[enemys[a].type].power;
								c=bullets[bulnum].power/5;
								c--;
								if(c>9)c=9;
								bullets[bulnum].picnum=c*32+5;
								bullets[bulnum].life=types_enemy[enemys[a].type].bullifetime;
								bullets[bulnum].pl=0;
								if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
							}
						}
						
					}
				}
				
				
				if(enemys[a].shoot_delay>0)enemys[a].shoot_delay++;
				if(enemys[a].shoot_delay>=types_enemy[enemys[a].type].shoot_delay)enemys[a].shoot_delay=0;
				//----------------------------------------------------------------------------------
				buldx=0;
				buldy=0;
				if(types_enemy[enemys[a].type].move_type==1)// chase
				{
					if(enemys[a].movdelay==0)
					{
						c=types_enemy[enemys[a].type].speed;
						enemys[a].movdelay=1;
						angle=fastangle(enemys[a].x-pl->x,enemys[a].y-pl->y);
						if (angle<0)angle+=360;
						ln=((enemys[a].x-pl->x)<<1)/(enemys[a].y-pl->y);
						c=types_enemy[enemys[a].type].speed;
						buldx=0;
						buldy=0;
						if(angle>=22&&angle<67)
						{
							buldx=-c;
							buldy=-c;
						}
						if(angle>=67&&angle<112)
						{
							buldx=-c;
							buldy=0;
						}
						if(angle>=112&&angle<157)
						{
							buldx=-c;
							buldy=c;
						}
						if(angle>=157&&angle<202)
						{
							buldx=0;
							buldy=c;
						}
						if(angle>=202&&angle<247)
						{
							buldx=c;
							buldy=c;
						}
						if(angle>=247&&angle<292)
						{
							buldx=c;
							buldy=0;
						}
						if(angle>=292&&angle<337)
						{
							buldx=c;
							buldy=-c;
						}
						if(ln<1&&(enemys[a].y-pl->y)>0)
						{
							buldx=0;
							buldy=-c;
						}
						if(ln<1&&(enemys[a].y-pl->y)<0)
						{
							buldx=0;
							buldy=c;
						}
						
						enemys[a].x+=buldx;
						enemys[a].y+=buldy;
						
					}
				}
				if(types_enemy[enemys[a].type].move_type==2)// chase
				{
					if(enemys[a].movdelay==0)
					{
						c=types_enemy[enemys[a].type].speed;
						enemys[a].movdelay=1;
					
						x=(enemys[a].x+4);
						x=x>>3;
						y=(enemys[a].y+8);
						y=y>>4;
						xx=pathfind[x][y];
						buldx=0;
						buldy=0;
						
						if(pathfind[x-1][y-1]<xx&&pathfind[x-1][y-1]!=0)
						{
							buldx=-c;
							buldy=-c;
						}
						if(pathfind[x][y-1]<xx&&pathfind[x][y-1]!=0)
						{
							buldx=0;
							buldy=-c;
						}
						if(pathfind[x+1][y-1]<xx&&pathfind[x+1][y-1]!=0)
						{
							buldx=c;
							buldy=-c;
						}
						if(pathfind[x-1][y+1]<xx&&pathfind[x-1][y+1]!=0)
						{
							buldx=-c;
							buldy=c;
						}
						if(pathfind[x][y+1]<xx&&pathfind[x][y+1]!=0)
						{
							buldx=0;
							buldy=c;
						}
						if(pathfind[x+1][y+1]<xx&&pathfind[x+1][y+1]!=0)
						{
							buldx=c;
							buldy=c;
						}
						if(pathfind[x+1][y]<xx&&pathfind[x+1][y]!=0)
						{
							buldy=0;
							buldx=c;
						}
						if(pathfind[x-1][y]<xx&&pathfind[x-1][y]!=0)
						{
							buldy=0;
							buldx=-c;
						}

							
						enemys[a].x+=buldx;
						enemys[a].y+=buldy;
						
					}
				}
				if(enemys[a].movdelay>0)enemys[a].movdelay++;
				if(enemys[a].dead==0)
				{
					spr=enemys[a].picnum;
					if(enemys[a].movdelay>=types_enemy[enemys[a].type].move_delay)enemys[a].movdelay=0;
					b=gn_napr(buldx,buldy);
					if(b!=128)enemys[a].lnapr=b;
					else b=enemys[a].lnapr;
					if(b==128)b=1;
					if(types_enemy[enemys[a].type].numinmas==1)
					{
						spr+=b*32;
					}
					//----------------------------------------------------------------------------------
					if(enemys[a].animframe<3)
					{
						set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,spr+enemys[a].animframe);
					}
					else set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,spr+1);
				}
				//else set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,enemys[a].picnum);
				enemys[a].animdelay++;
				if(enemys[a].animdelay>=enemyanimdelay)
				{
					enemys[a].animdelay=0;
					enemys[a].animframe++;
					if(enemys[a].animframe==4)enemys[a].animframe=0;
				}
				if(enemys[a].health<=0)
				{
					enemys[a].dead=1;
					if(is_final_battle==0)
					{
						enemys[a].coin=1;
						c=rand16()%bonus_variant;
						//-------------------------
						//c=1;
						//------------------------
						if(c==1)//бонус
						{
							b=rand16()%12;
							//b=11;
							enemys[a].type_bonus=b;
							enemys[a].picnum=320+(b<<5);
							//enemys[a].picnum=320;
						}
						else//монетка
						{
							enemys[a].picnum=38;
							enemys[a].type_bonus=32;
						}
					}
					else
					{
							set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,enemys[a].picnum);
							enemys[a].coin=0;
							spritenums[enemys[a].sprnum]=0;
							enemys[a].sprnum=128;
							
					}
					//set_sprite(63,enemys[a].x,enemys[a].y,enemys[a].picnum);
				}
			}
		}
		if(enemys[a].dead==1&&enemys[a].coin>0)
		{
			enemys[a].animdelay++;
			if(enemys[a].animdelay>=enemyanimdelay)
			{
				enemys[a].animdelay=0;
				enemys[a].animframe++;
				if(enemys[a].animframe==4)enemys[a].animframe=0;
				
			}
			
			//**********************************************
		spr=enemys[a].picnum;


			//**********************************************
			if(enemys[a].coin==1)set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,spr+enemys[a].animframe);
			else
			{
				set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,3);
				enemys[a].coin++;
				if(enemys[a].coin>3)
				{
					enemys[a].coin=0;
					//spritenums[enemys[a].sprnum]=0;
				}
			}
		}
		
	}
}
void in_pause(Player *pl)
{
	u8 buf[32];
	u8 a,b,c,d;
	c=1;
	d=0;
	buf[0]='\0';
	fade_to_black();
    sprites_stop(); //!!
	for(a=0;a<32;a++)
	{
		if(spritenums[a]==1)set_sprite(a,1,1,3);
	}
	
//	swap_screen();
	pal_select(PAL_PAUSE2);
//	draw_image(0,0,IMG_PAUSE2);
//	swap_screen();
	//draw_image(0,0,IMG_PAUSE2);
	//swap_screen();
	select_image(IMG_FONT);
			//sprites_stop();
			draw_image(0,0,IMG_PAUSE2);
			if(pl->health>0)
			{
				atoi(pl->health,buf);
				output_x=34;
				output_y=2;
				put_str(buf);
			}
			
			atoi(pl->coins,buf);
			output_x=34;
			output_y=5;
			put_str(buf);
			
			atoi(pl->pwr,buf);
			output_x=34;
			output_y=8;
			put_str(buf);
			
			atoi(pl->speed,buf);
			output_x=34;
			output_y=11;
			put_str(buf);
			
			atoi((20-pl->shoot_spd),buf);
			output_x=34;
			output_y=14;
			put_str(buf);
			
			atoi(pl->bullifetime,buf);
			output_x=34;
			output_y=17;
			put_str(buf);
			
			atoi(pl->bulspeed,buf);
			output_x=34;
			output_y=20;
			put_str(buf);
			
			atoi(dif_cnt_levels[curdif]-curlevel,buf);
			output_x=12;
			output_y=20;
			put_str(buf);
			select_image(IMG_TILES);
			for(a=0;a<16;a++)
			{
				for(b=0;b<16;b++)
				{
					if(cleared[a][b]==1)
					{
						if(global_rooms[a][b]!=254)
						{
							draw_tile(a,b,20);
						}
						else
						{
							draw_tile(a,b,23);
						}
					}
					else draw_tile(a,b,21);
				}
			}
			draw_tile(stroomx,stroomy,22);
		
		swap_screen();
        sprites_start();
	fade_from_black();
	while(c)
	{
		if(d==0)
		{
			d++;
			
		}
		keyboard(keys);
		if(keys[KEY_ENTER]==KEY_DOWN)
		{
				c=0;
				//fade_to_black();
		}
	}
	opened=0;
	fade_to_black();
    sprites_stop();
	select_image(IMG_TILES);
	//clear_screen(0);
	//swap_screen();
	//clear_screen(0);
	//only_redraw=1;
	//d=cleared[stroomx][stroomy];
	//sprites_start();
//	clear_screen(0);
//	swap_screen();
//	clear_screen(0);
	redraw_map(global_rooms[stroomx][stroomy]);
   //draw_map(global_rooms[stroomx][stroomy],0);
	
	//only_redraw=0;
	pal_select(PAL_TILES);
	print_pl_health(pl);
    swap_screen();
    sprites_start();
	fade_from_black();
}
void pl_fire_diag(Player *pl,u8 power,u8 dist)
{
	u8 b,c,bulnum,sprnum;
	i16 buldx,buldy;
	for(b=0;b<4;b++)
			{
				bulnum=find_free_bullet();
				if(bulnum!=64)
				{
					sprnum=find_free_sprite();
					if (sprnum!=128)
					{
						buldx=0;
						buldy=0;
						c=pl->bulspeed;
						if(b==0)
						{
							buldx=c;
							buldy=-c;
						}
						if(b==1)
						{
							buldx=-c;
							buldy=-c;
						}
						if(b==2)
						{
							buldx=-c;
							buldy=c;
						}
						if(b==3)
						{
							buldx=c;
							buldy=c;
						}
				
						if(buldx!=0||buldy!=0)
						{
							buldy<<=1;
							bullets[bulnum].x=pl->x+4;
							bullets[bulnum].y=pl->y+8;
							bullets[bulnum].dx=buldx;
							bullets[bulnum].dy=buldy;
							bullets[bulnum].isfree=0;
							bullets[bulnum].sprnum=sprnum;
							spritenums[bullets[bulnum].sprnum]=1;
							
							
							c=(power)/5;
							c--;
							if(c>17)c=17;
							bullets[bulnum].picnum=c*32+4;

							bullets[bulnum].power=power;
							bullets[bulnum].pl=1;
							bullets[bulnum].life=dist;
							
						}
					}
				}
			}
}
void pl_fire_ax(Player *pl,u8 power,u8 dist)
{
	u8 b,c,bulnum,sprnum;
	i16 buldx,buldy;
	for(b=4;b<8;b++)
			{
				bulnum=find_free_bullet();
				if(bulnum!=64)
				{
					sprnum=find_free_sprite();
					if (sprnum!=128)
					{
						buldx=0;
						buldy=0;
						c=pl->bulspeed;
						
						if(b==4)
						{
							buldx=c;
							buldy=0;
						}
						if(b==5)
						{
							buldx=-c;
							buldy=0;
						}
						if(b==6)
						{
							buldx=0;
							buldy=c;
						}
						if(b==7)
						{
							buldx=0;
							buldy=-c;
						}
						if(buldx!=0||buldy!=0)
						{
							buldy<<=1;
							bullets[bulnum].x=pl->x+3;
							bullets[bulnum].y=pl->y+8;
							bullets[bulnum].dx=buldx;
							bullets[bulnum].dy=buldy;
							bullets[bulnum].isfree=0;
							bullets[bulnum].sprnum=sprnum;
							spritenums[bullets[bulnum].sprnum]=1;
							
							
							c=(power)/5;
							c--;
							if(c>17)c=17;
							bullets[bulnum].picnum=c*32+4;

							bullets[bulnum].power=power;
							bullets[bulnum].pl=1;
							bullets[bulnum].life=dist;
							
						}
					}
				}
			}
}
void act_bonuse(Player *pl,u8 num)
{
	u8 a,b,c,bulnum,sprnum;
	i16 buldx,buldy;
	if(pl->bonuses[num]!=32)
	{
		if(pl->bonuses[num]==0)pl->health+=10;
		if(pl->bonuses[num]==1)
		{
			if(pl->shoot_spd-8>2)pl->shoot_spd-=8;
			else pl->shoot_spd=2;
		}
		if(pl->bonuses[num]==3)
		{
			pl->pwr<<=1;
		}
		if(pl->bonuses[num]==4)
		{
			pl->bullifetime=100;
		}
		if(pl->bonuses[num]==5)
		{
			if (bonus_variant>5)bonus_variant-=2;
		}
		if(pl->bonuses[num]==2)
		{
			pl_fire_ax(pl,pl->pwr<<2,pl->bullifetime<<1);
			pl_fire_diag(pl,pl->pwr<<2,pl->bullifetime<<1);
		}
		if(pl->bonuses[num]==6)
		{
			pl_fire_ax(pl,pl->pwr<<2,pl->bullifetime<<2);
		}
		if(pl->bonuses[num]==7)
		{
			pl_fire_diag(pl,pl->pwr<<2,pl->bullifetime<<2);
		}
		if(pl->bonuses[num]==8)pl->health+=20;
		if(pl->bonuses[num]==9)pl->speed+=1;
		if(pl->bonuses[num]==10)
		{
			for(a=0;a<8;a++)
			{
				bulnum=find_free_bullet();
				if(bulnum!=64)
				{
					sprnum=find_free_sprite();
					if (sprnum!=128)
					{

						bullets[bulnum].x=pl->x+2+bbdx[a];
						bullets[bulnum].y=pl->y+4+bbdy[a];
						bullets[bulnum].dx=0;
						bullets[bulnum].dy=0;
						bullets[bulnum].isfree=0;
						bullets[bulnum].sprnum=sprnum;
						spritenums[bullets[bulnum].sprnum]=1;									

						c=17;
						bullets[bulnum].picnum=c*32+4;
						bullets[bulnum].power=pl->pwr<<4;
						bullets[bulnum].pl=1;
						bullets[bulnum].life=500;
					}
				}
			}
		}
		if(pl->bonuses[num]==11) monpause=150;
		pl->bonuses[num]=32;
		print_pl_health(pl);
	}

}
void move_player(Player *pl)
{
	int joy;
	u8 bulnum,x,y,xx,yy,sprnum,x2,y2,xx2,yy2,a,d,bb;
	i8 buldx,buldy,dx,dy;
	u16 c;
	//pdx=0;
	//dy=0;
	keyboard(keys);
	    joy=joystick();
		x2=(pl->x+2)>>3;
		y2=(pl->y+8)>>4;
		xx2=(pl->x+8-2)>>3;
		yy2=(pl->y+16-2)>>4;
		//x3=(pl->x+4)>>3;
		//y3=(pl->y+8)>>4;
		xx=curmap_tiles[x2][y2];
		yy=curmap_tiles[xx2][yy2];
	
		if(xx!=4||yy!=4)
		{
			pdx=0;
			pdy=0;
		}
	    if(keys[KEY_D]==KEY_DOWN)
		{
				//pdx=pl->speed>>1;
				pdx=pl->speed;
				
				//pl->x++;
		}
		if(keys[KEY_A]==KEY_DOWN)
		{
				//pdx=-pl->speed>>1;
				pdx=-pl->speed;
				//pl->x--;
		}
		if(keys[KEY_1]==KEY_DOWN)act_bonuse(pl,0);
		if(keys[KEY_2]==KEY_DOWN)act_bonuse(pl,1);
		if(keys[KEY_3]==KEY_DOWN)act_bonuse(pl,2);
		if(keys[KEY_4]==KEY_DOWN)act_bonuse(pl,3);
		if(keys[KEY_9]==KEY_DOWN)
		{	
			//вкл/выкл звука
			if(sndon==1)sndon=2;
			else sndon=1;
			delay(4);
		}
		if(keys[KEY_0]==KEY_DOWN)
		{	
			//вкл/выкл музыки
			if(muson==1)
			{
				muson=2;
				music_stop();
			}
			else 
			{
				muson=1;
				music_play(lastmus);
			}
			delay(4);
		}
		if(keys[KEY_W]==KEY_DOWN)
		{
				pdy=-pl->speed<<1;
				//pl->y-=2;
		}
		if(keys[KEY_S]==KEY_DOWN)
		{
				pdy=pl->speed<<1;
				//pl->y+=2;
		}
		if(keys[KEY_ENTER]==KEY_DOWN && is_final_battle==0)
		{
				in_pause(pl);

		}
		if(xx==18||yy==18)
		{
			pdy>>=1;
			if(pdx>1)pdx>>=1;
		}
		if((xx==17||yy==17)&&pl->damaged==0)
		{
			pl->damaged=1;
			pl->anim_frame=32;
			pl->health-=10;
			print_pl_health(pl);
		}
		x=(pl->x+pdx+2)>>3;
		y=(pl->y+pdy+8)>>4;
		xx=(pl->x+8+pdx-2)>>3;
		yy=(pl->y+16+pdy-2)>>4;
		
		for(a=0;a<count_enemys;a++)
		{
			c=255;
			if(enemys[a].dead==0||(enemys[a].dead==1&& enemys[a].coin==1))
			{
				//c=lsqrt(((pl->x-enemys[a].x)*(pl->x-enemys[a].x))+(pl->y-enemys[a].y)*(pl->y-enemys[a].y));
				if((pl->x>=enemys[a].x&&pl->y+1>=enemys[a].y&&pl->x<=enemys[a].x+8&&pl->y+1<=enemys[a].y+16) ||(pl->x+8>=enemys[a].x&&pl->y+15>=enemys[a].y&&pl->x+8<=enemys[a].x+8&&pl->y+15<=enemys[a].y+16))
				{
					c=1;
				}
			}
			if(enemys[a].dead==0&&pl->damaged==0)
			{
				
				if (c==1)
				{
					
					pl->damaged=1;
					pl->anim_frame=32;
					pl->health-=types_enemy[enemys[a].type].power;
					print_pl_health(pl);
				}
			}
			if(enemys[a].dead==1 && enemys[a].coin==1)
			{
				if (c==1||is_final_battle==1)
				{
					if(is_final_battle==0)
					{
						
						if(enemys[a].type_bonus==32)
						{
							if(sndon==1)sfx_play(SFX_COIN,7);
							pl->coins++;
							//enemys[a].coin++;
						}
						else
						{
							bb=0;
							for(d=0;d<4;d++)
							{
								if (pl->bonuses[d]==32)
								{
									pl->bonuses[d]=enemys[a].type_bonus;
									//enemys[a].coin++;
									d=4;
									bb=1;
								}
							}
							if(bb==0)pl->coins++;
							if(sndon==1)sfx_play(SFX_COIN,7);
						}
						enemys[a].coin++;
						print_pl_health(pl);
					}
					
				}
			}
		}
		
		if(pathfind[x][y2]==255||pathfind[xx][y2]==255||pathfind[x][yy2]==255||pathfind[xx][yy2]==255)
		{
			pdx=0;
		}
		if(pathfind[x2][y]==255||pathfind[xx2][y]==255||pathfind[x2][yy]==255||pathfind[xx2][yy]==255)
		{
			pdy=0;
		}
		if(opened==1)
		{

			cleared[stroomx][stroomy]=1;
			if(pl->x+pdx<4)
			{
				stroomx--;
				pl->x=144;
				pdx=0;
				opened=0;
				bulnum=cleared[stroomx][stroomy];
				
				fade_to_black();
				sprites_stop();
				only_redraw=0;
				if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				else draw_map(global_rooms[stroomx][stroomy],0);
				only_redraw=1;
                swap_screen(); // !!
				sprites_start();
				// !! if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				// !! else draw_map(global_rooms[stroomx][stroomy],0);
				print_pl_health(pl);
				fade_from_black();
				pl->bullifetime=pl->old_bullifetime;
				pl->pwr=pl->old_pwr;
				pl->shoot_spd=pl->old_shoot_spd;
				pl->speed=pl->old_speed;
			}
			if(pl->x+pdx>146)
			{
				stroomx++;
				pl->x=8;
				pdx=0;
				opened=0;
				bulnum=cleared[stroomx][stroomy];
					fade_to_black();
				sprites_stop();
				only_redraw=0;
				if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				else draw_map(global_rooms[stroomx][stroomy],0);
				only_redraw=1;
                swap_screen();
				sprites_start();
				// !! if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				// !! else draw_map(global_rooms[stroomx][stroomy],0);
				print_pl_health(pl);
				fade_from_black();
				pl->bullifetime=pl->old_bullifetime;
				pl->pwr=pl->old_pwr;
				pl->shoot_spd=pl->old_shoot_spd;
				pl->speed=pl->old_speed;
			}
			if(pl->y+pdy<4)
			{
				stroomy--;
				pl->y=160;
				pdy=0;
				opened=0;
				bulnum=cleared[stroomx][stroomy];
				fade_to_black();
				sprites_stop();
				only_redraw=0;
				if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				else draw_map(global_rooms[stroomx][stroomy],0);
				only_redraw=1;
                swap_screen();
				sprites_start();
				// !! if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				// !! else draw_map(global_rooms[stroomx][stroomy],0);
				print_pl_health(pl);
				fade_from_black();
				pl->bullifetime=pl->old_bullifetime;
				pl->pwr=pl->old_pwr;
				pl->shoot_spd=pl->old_shoot_spd;
				pl->speed=pl->old_speed;
			}
			if(pl->y+pdy>=168)
			{
				stroomy++;
				pl->y=16;
				pdy=0;
				opened=0;
				bulnum=cleared[stroomx][stroomy];
				fade_to_black();
				sprites_stop();
				only_redraw=0;
				if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				else draw_map(global_rooms[stroomx][stroomy],0);
				only_redraw=1;
                swap_screen();
				sprites_start();
				// !! if(bulnum==0)draw_map(global_rooms[stroomx][stroomy],1);
				// !! else draw_map(global_rooms[stroomx][stroomy],0);
				print_pl_health(pl);
				fade_from_black();
				pl->bullifetime=pl->old_bullifetime;;
				pl->pwr=pl->old_pwr;
				pl->shoot_spd=pl->old_shoot_spd;
				pl->speed=pl->old_speed;
			}
			
		}
		//----------------------
		
		pl->x+=pdx;
		pl->y+=pdy;
		//------------------------------------------
		buldx=0;
		buldy=0;
		if(joy&JOY_RIGHT>0)
		{
			//buldx=pl->bulspeed>>1;
			buldx=pl->bulspeed;
		}
		if(joy&JOY_LEFT>0)
		{
				//buldx=-pl->bulspeed>>1;
				buldx=-pl->bulspeed;
		}
		if(joy&JOY_UP>0)
		{
				buldy=-pl->bulspeed<<1;
		}
		if(joy&JOY_DOWN>0)
		{
				buldy=pl->bulspeed<<1;
		}
		if((buldx!=0||buldy!=0)&&pl->shoot_delay==0)
		{
			
			bulnum=find_free_bullet();
			sprnum=find_free_sprite_bul();
			if((bulnum!=64) && (sprnum!=128))
			{
				bullets[bulnum].x=pl->x+3;
				bullets[bulnum].y=pl->y+8;
				bullets[bulnum].dx=buldx;
				bullets[bulnum].dy=buldy;
				bullets[bulnum].isfree=0;
				bullets[bulnum].sprnum=sprnum;
				
				spritenums[bullets[bulnum].sprnum]=1;
				c=pl->pwr/5;
				c--;
				if(c>18)c=18;
				bullets[bulnum].picnum=c*32+4;
				//bullets[bulnum].picnum=4;
				bullets[bulnum].power=pl->pwr;
				bullets[bulnum].pl=1;
				bullets[bulnum].life=pl->bullifetime;
				pl->shoot_delay++;
				if(sndon==1)sfx_play(SFX_FIRE,7);
			}
		}
		//---------------------------------------------
		pl->tanim_frame++;
		
		if(pl->shoot_delay>0)
		{
			pl->shoot_delay++;
			if(pl->shoot_delay>=pl->shoot_spd) pl->shoot_delay=0;
		}
		if(pl->tanim_frame>=16)
		{
			if(pl->damaged==1&&dmg_played==0)
			{
				if(sndon==1)sfx_play(SFX_DAMAGE,8);
				dmg_played=1;
			}
			pl->anim_frame++;
			pl->tanim_frame=0;
			if(pl->anim_frame>2&&pl->damaged==0)
			{
				pl->anim_frame=0;
				dmg_played=0;
			}
			if(pl->anim_frame>34&&pl->damaged>0)
			{
				pl->anim_frame=32;
				pl->damaged++;
				
			}
			
			if(pl->damaged>1)	pl->damaged=0;

		}
		if(global_rooms[stroomx][stroomy]==254)
		{
			if(pl->x>=64&&pl->x<=88&&pl->y>=64&&pl->y<=112)ingame=0;
		}
		if(pl->health<=0)
		{
			pldead=0;
			ingame=0;
			music_stop();
			sprites_stop();
			fade_to_black();
			pal_select(PAL_GAME_OVER);
			draw_image(0,0,IMG_GAME_OVER);
			swap_screen();
			draw_image(0,0,IMG_GAME_OVER);
			swap_screen();
			fade_from_black();
			sample_play(SMP_BELL);
			delay(42);
			
		}
}

void in_shop(Player *pl)
{	
	u8 str[16],a,pos;
	u8 f,ff;
	int joy;
	//Жизнь,скорость,сила,скорострельность,дальность,скорость пули
	u8 prices[]={2,50,10,10,10,20};
	u16 max_vals[]={2048,8,255,2,100,10};
	u8 chvals[]={10,1,5,2,5,1};
	fade_to_black();
	sprites_start();
	pos=0;
	f=1;
	ff=1;
	
	pal_select(PAL_SHOP);
	draw_image(0,0,IMG_SHOP);
	swap_screen();
	fade_from_black();
	while(f)
	{
		ff=1;		
		draw_image(0,0,IMG_SHOP);
		atoi(pl->coins,str);
		output_x=32;
		output_y=3;
		put_str(str);
		
		atoi(pl->health,str);
		output_x=22;
		output_y=7;
		put_str(str);
		
		atoi(pl->speed,str);
		output_x=22;
		output_y=10;
		put_str(str);
		
		atoi(pl->pwr,str);
		output_x=22;
		output_y=13;
		put_str(str);
		
		atoi((20-pl->shoot_spd),str);
		output_x=22;
		output_y=16;
		put_str(str);
		
		atoi(pl->bullifetime,str);
		output_x=22;
		output_y=19;
		put_str(str);
		
		atoi(pl->bulspeed,str);
		output_x=22;
		output_y=22;
		put_str(str);
		
		while(ff)
		{
			joy=joystick();
			keyboard(keys);
			for(a=0;a<6;a++)
			{
				atoi(prices[a],str);
				output_x=32;
				output_y=7+a*3;
				put_str(str);
			}
			
			//------------
			if(keys[KEY_Q]==KEY_DOWN)
			{
					f=0;
					ff=0;
			}
			if(keys[KEY_ENTER]==KEY_DOWN)
			{
				if(sndon==1)sfx_play(SFX_MENU,7);
				if(pl->coins>=prices[pos])
				{
					switch(pos)
					{
						case 0:
						{
							if(pl->health+chvals[pos]<max_vals[pos])
							{
								pl->health+=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}
						case 1:
						{
							if(pl->speed+chvals[pos]<max_vals[pos])
							{
								pl->speed+=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}

					
						case 2:
						{
							if(pl->pwr+chvals[pos]<max_vals[pos])
							{
								pl->pwr+=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}
						case 3:
						{
							if(pl->shoot_spd-chvals[pos]>max_vals[pos])
							{
								pl->shoot_spd-=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}
						case 4:
						{
							if(pl->bullifetime+chvals[pos]<max_vals[pos])
							{
								pl->bullifetime+=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}
						case 5:
						{
							if(pl->bulspeed+chvals[pos]<max_vals[pos])
							{
								pl->bulspeed+=chvals[pos];
								pl->coins-=prices[pos];
								
							}
							break;
						}
					}
					
					ff=0;
				}
			}
			if(joy&JOY_UP>0)
			{
				if(sndon==1)sfx_play(SFX_MENU,7);
				if(pos>0)pos--;
				delay(2);
			}
			if(joy&JOY_DOWN>0)
			{
				if(sndon==1)sfx_play(SFX_MENU,7);
				if(pos<5)pos++;
				delay(2);
			}
			set_sprite(0,110,52+pos*24,42);
			swap_screen();
		}
	}
	fade_to_black();
	pal_select(PAL_TILES);
}
void inintro(u8 picnum,u8 palnum,u8* str)
{
	
	pal_select(palnum);
	draw_image(0,0,picnum);
	swap_screen();
	
	draw_image(0,0,picnum);
	swap_screen();
	fade_from_black();
	delay(32);
	draw_image(0,0,picnum);
	swap_screen();
	output_x=2;
	output_y=23;
	put_str(str);
	swap_screen();
	delay(160);
	fade_to_black();
}
void inintro2(u8 y,u8 *str,u8 del)
{

	output_x=2;
	output_y=y;
	put_str(str);
	swap_screen();
	sfx_play(SFX_INTRO1,7);
	delay(del);
}
void show_outro()
{
	u8 a,b;
	sprites_stop();
	color_key(4);
	//pcharmask=1;
	fade_to_black();
	/*pal_select(PAL_OUTRO1);
	draw_image(0,0,IMG_OUTRO1);
	swap_screen();
	delay(160);*/
	lastmus=outromus;
	if(muson==1)music_play(outromus);
	inintro(IMG_OUTRO1,PAL_OUTRO1,"");
	inintro(IMG_OUTRO2,PAL_OUTRO2,"");
	inintro(IMG_OUTRO3,PAL_OUTRO3,"");
	inintro(IMG_OUTRO4,PAL_OUTRO4,"");
	inintro(IMG_OUTRO5,PAL_OUTRO5,"");
	clear_screen(4);
	swap_screen();
	clear_screen(4);
	
	pal_select(PAL_MAIN4);
	for(a=0;a<2;a++)
	{
		output_x=13;
		output_y=0;
		put_str("Надмозг побежден. ");
		//output_x=3;
		//output_y=3;
		//put_str("Остатки его армии дочистят отряды       службы охраны.");
		output_x=13;
		output_y=7;
		put_str("Отличная работа");
		output_x=1;
		output_y=9;
		if(curdif==0)
		{
			put_str("Это было всего лишь первое знакомство с игрой. Играйте дальше на более      высокой сложности и вас ожидаю новые  этажи и более сильные и многочисленныесоперники.");
		}
		if(curdif==1)
		{
			put_str("Это было легко. Так ведь? ;) Как      насчет повышения сложности?");
		}
		if(curdif==2)
		{
			put_str("Уже приближаетесь к нормальной        сложности. Продолжайте в том-же духе.");
		}
		if(curdif==3)
		{
			put_str("Очень хорошо. Мои поздравления. Дальшеэтого уровня сложности автор игру     пройти не смог. А вы сможете?");
		}
		if(curdif==4)
		{
			put_str("Дизинформация автор уже прошел эту    сложность, но все равно снимаю шляпу :)Это было сложно, но может немного      усложним задачу?");
		}
		if(curdif==5)
		{
			put_str("Да вы просто мега игрок. Остался последний, самый монструозный и            непроходимый уровень сложности.");
		}
		if(curdif==6)
		{
			put_str("Мне кажется, что кто-то тут читерит ;) Эту сложность не проходил ни кто.");
		}
	
		if(curdif<6)
		{
			output_x=12;
			output_y=21;
			put_str("Пароль: ");
			put_str(passwords[curdif]);
		}
		output_x=9;
		output_y=23;
		put_str("Нажмите любую кнопку.");
		
		swap_screen();
	}
	fade_from_black();
	a=1;
	/*while(a)
	{
		keyboard(keys);
		for(b=0;b<255;b++)
		{
			if(keys[b]==KEY_DOWN)a=0;
			
		}
	}*/
	wait_a_key();
	maxdif++;
	if(maxdif>6)maxdif=6;
	curdif=maxdif;
}
void move_boss(Player *pl)
{
	u8 a,bulnum,sprnum,c,xx;
	i16 buldx,buldy,angle,ln;
	i16 b;
	b=0;
	buldx=buldy=0;
	for(a=0;a<8;a++)
	{
		/*if(enemys[a].coin>0&&enemys[a].dead==1)
		{
			pl->x++;
			enemys[a].coin=0;
			enemys[a].dead=1;
			//set_sprite(enemys[a].sprnum,enemys[a].x,enemys[a].y,3);
			//spritenums[enemys[a].sprnum]=0;
		}*/
		if(enemys[a].dead==0)b++;
	}
	if(b<dif_final_count_mon[curdif])
	{
		count_enemys=dif_final_count_mon[curdif]+1;
		
		
		//boss_cur_shoot_delay++;
		a=rand16()%2;
		if(a==0)
		{
			buldx=24;
			buldy=64;
		}
		if(a==1)
		{
			buldx=128;
			buldy=64;
		}
		a=255;
		for(b=0;b<8;b++)
		{
			if(enemys[b].dead==1)
			{	
				a=b;
				//pl->x=a*16;
				b=8;
			}
		}
		if(a!=255)
		{
			
			b=find_free_sprite();
			

			if (b!=128)
			{
				pl->x++;
				enemys[a].sprnum=b;
				b=rand16()%4;
				//b=0;
				enemys[a].x=buldx;
				enemys[a].y=buldy;
				enemys[a].type=b;
				enemys[a].dead=0;
				enemys[a].health=types_enemy[b].health;
				enemys[a].picnum=types_enemy[b].picnum;
				
				enemys[a].movdelay=types_enemy[b].move_delay;
			
				spritenums[enemys[a].sprnum]=1;
				enemys[a].animframe=rand16()%4;
				enemys[a].animdelay=rand16()%enemyanimdelay;
				enemys[a].coin=0;
				enemys[a].shoot_delay=rand16()%types_enemy[b].shoot_delay;
			}
			//pl->x=15;
		}
	}
	boss_cur_shoot_delay++;
	if(boss_cur_shoot_delay>=boss_shoot_delay)boss_cur_shoot_delay=0;
	//boss_cur_shoot_delay=1;
	if(boss_cur_shoot_delay==0)
	{
		boss_cur_shot_type++;
		if(boss_cur_shot_type>3)boss_cur_shot_type=1;
		xx=rand16()%24+64;
			if (boss_cur_shot_type==2)
				{
					for(b=0;b<4;b++)
					{
						bulnum=find_free_bullet();
	
						if(bulnum!=64)
						{
							sprnum=find_free_sprite();
							if (sprnum!=128)
							{
								buldx=0;
								buldy=0;
								c=4;
								if(b==0)
								{
									buldx=c;
									buldy=-c;
								}
								if(b==1)
								{
									buldx=-c;
									buldy=-c;
								}
								if(b==2)
								{
									buldx=-c;
									buldy=c;
								}
								if(b==3)
								{
									buldx=c;
									buldy=c;
								}
								if(buldx!=0||buldy!=0)
								{
								buldy<<=1;
								bullets[bulnum].x=xx;
								bullets[bulnum].y=70;
								bullets[bulnum].dx=buldx;
								bullets[bulnum].dy=buldy;
								bullets[bulnum].isfree=0;
								bullets[bulnum].sprnum=sprnum;
								spritenums[bullets[bulnum].sprnum]=1;
								//bullets[bulnum].picnum=5;
								bullets[bulnum].power=dif_final_brain_power[curdif];
								if(bullets[bulnum].power>0&&bullets[bulnum].power<=25)bullets[bulnum].picnum=5;
								if(bullets[bulnum].power>25&&bullets[bulnum].power<=50)bullets[bulnum].picnum=37;
								if(bullets[bulnum].power>50&&bullets[bulnum].power<=75)bullets[bulnum].picnum=69;
								if(bullets[bulnum].power>75)bullets[bulnum].picnum=101;
								bullets[bulnum].life=120;
								bullets[bulnum].pl=0;
								}
							}
						}
					}
					if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
				}
				if (boss_cur_shot_type==3)
				{
				
					for(b=0;b<4;b++)
					{
						bulnum=find_free_bullet();
	
						if(bulnum!=64)
						{
							sprnum=find_free_sprite();
							if (sprnum!=128)
							{
								buldx=0;
								buldy=0;
								c=4;
								if(b==0)
								{
									buldx=0;
									buldy=-c;
								}
								if(b==1)
								{
									buldx=-c;
									buldy=0;
								}
								if(b==2)
								{
									buldx=0;
									buldy=c;
								}
								if(b==3)
								{
									buldx=c;
									buldy=0;
								}
								if(buldx!=0||buldy!=0)
								{
									buldy<<=1;
									bullets[bulnum].x=xx;
									bullets[bulnum].y=70;
									bullets[bulnum].dx=buldx;
									bullets[bulnum].dy=buldy;
									bullets[bulnum].isfree=0;
									bullets[bulnum].sprnum=sprnum;
									spritenums[bullets[bulnum].sprnum]=1;
									//bullets[bulnum].picnum=5;
									bullets[bulnum].power=dif_final_brain_power[curdif];
									if(bullets[bulnum].power>0&&bullets[bulnum].power<=25)bullets[bulnum].picnum=5;
									if(bullets[bulnum].power>25&&bullets[bulnum].power<=50)bullets[bulnum].picnum=37;
									if(bullets[bulnum].power>50&&bullets[bulnum].power<=75)bullets[bulnum].picnum=69;
									if(bullets[bulnum].power>75)bullets[bulnum].picnum=101;
									bullets[bulnum].life=100;
									bullets[bulnum].pl=0;
								}
							}
						}
					}
					if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
				}
				if (boss_cur_shot_type==1)
				{
					bulnum=find_free_bullet();
					sprnum=find_free_sprite();
					if(bulnum!=64&&sprnum!=128)
					{
						
						buldx=0;
						buldy=0;
						angle=fastangle(75-pl->x,70-pl->y);
						if (angle<0)angle+=360;
						ln=((75-pl->x)<<1)/(70-pl->y);
						c=4;
						if(angle>=22&&angle<67)
						{
							buldx=-c;
							buldy=-c;
						}
						if(angle>=67&&angle<112)
						{
							buldx=-c;
							buldy=0;
						}
						if(angle>=112&&angle<157)
						{
							buldx=-c;
							buldy=c;
						}
						if(angle>=157&&angle<202)
						{
							buldx=0;
							buldy=c;
						}
						if(angle>=202&&angle<247)
						{
							buldx=c;
							buldy=c;
						}
						if(angle>=247&&angle<292)
						{
							buldx=c;
							buldy=0;
						}
						if(angle>=292&&angle<337)
						{
							buldx=c;
							buldy=-c;
						}
						if(ln<1&&(70-pl->y)>0)
						{
							buldx=0;
							buldy=-c;
						}
						if(ln<1&&(70-pl->y)<0)
						{
							buldx=0;
							buldy=c;
						}
						buldy*=2;
						if(buldx!=0||buldy!=0)
						{
							bullets[bulnum].x=xx+3;
							bullets[bulnum].y=70+8;
							bullets[bulnum].dx=buldx;
							bullets[bulnum].dy=buldy;
							bullets[bulnum].isfree=0;
							bullets[bulnum].sprnum=find_free_sprite();

							spritenums[bullets[bulnum].sprnum]=1;
							//bullets[bulnum].picnum=5;
							bullets[bulnum].power=dif_final_brain_power[curdif];
							if(bullets[bulnum].power>0&&bullets[bulnum].power<=25)bullets[bulnum].picnum=5;
							if(bullets[bulnum].power>25&&bullets[bulnum].power<=50)bullets[bulnum].picnum=37;
							if(bullets[bulnum].power>50&&bullets[bulnum].power<=75)bullets[bulnum].picnum=69;
							if(bullets[bulnum].power>75)bullets[bulnum].picnum=101;
							bullets[bulnum].life=100;
							bullets[bulnum].pl=0;
							if(sndon==1)sfx_play(SFX_ENEMY_FIRE,7);
						}
					}
					
				}
		
		
	}
	if(boss_health<=0)
	{	
		
		for(b=0;b<3;b++)
		{
			for(a=1;a<32;a++)
			{
				if(bullets[a].isfree!=1)
				{
					set_sprite(bullets[a].sprnum,bullets[a].x,bullets[a].y,3);
				}
			}
			swap_screen();
		}
		b=0;
		for(a=1;a<64&&b<16;a++)
		{
			if(spritenums[a]==0)
			{
				buldx=rand16()%24;
				buldy=rand16()%64;
				buldx+=64;
				buldy+=32;
				set_sprite(a,buldx,buldy,rand16()%3*32+67);
				swap_screen();
				if(sndon==1)sfx_play(SFX_BOSS,7);
				delay(12);
				b++;
			}
		}
		show_outro();
		pldead=0;
		ingame=0;
	}
}
void in_game(Player *pl)
{
	
	ingame=1;
	while (ingame)
	{
		
		output_x=0;
		output_y=0;
		//_ltoa(12,&buf,1);
		
		if(currecalc==0&&liveenemys==1)
		{
			free_path();
			path_pl(pl);
			currecalc=1;
		}
		if(currecalc!=0)currecalc++;
		if(currecalc==pathrecalc)currecalc=0;
		if(opened==0&&liveenemys==0)//открытие дверей
		{	
			cleared[stroomx][stroomy]=1;
			opened=1;
			if(stroomx+1<16)
			{
				if(global_rooms[stroomx+1][stroomy]!=255)
				{
					pathfind[19][6]=0;
					pathfind[19][5]=0;
					print_tile(38,12,prespath+32,2,32,0);
					print_tile(38,10,prespath,2,32,0);
				}
			}
			if(stroomx-1>=0)
			{
				if(global_rooms[stroomx-1][stroomy]!=255)
				{
					pathfind[0][6]=0;
					pathfind[0][5]=0;
					print_tile(0,12,prespath+48,2,32,0);
					print_tile(0,10,prespath+16,2,32,0);
				}
			}
			if(stroomy+1<16)
			{
			if(global_rooms[stroomx][stroomy+1]!=255)
				{
					pathfind[10][11]=0;
					pathfind[9][11]=0;
					pathfind[8][11]=0;
					print_tile(20,22,prespath+16,2,32,0);
					print_tile(18,22,prespath,2,32,0);
					print_tile(16,22,prespath+16,2,32,0);
				}
			}
			if(stroomy-1>=0)
			{
				if(global_rooms[stroomx][stroomy-1]!=255)
				{
					pathfind[10][0]=0;
					pathfind[9][0]=0;
					pathfind[8][0]=0;
					print_tile(20,0,prespath+48,2,32,0);
					print_tile(18,0,prespath+32,2,32,0);
					print_tile(16,0,prespath+48,2,32,0);
				}
			}

		}
		//sprite_helper();
		move_player(pl);
		move_enemys(pl);
		move_bullets(pl);
		if(is_final_battle==1)move_boss(pl);
		
		set_sprite(0,pl->x,pl->y,pl->anim_frame);
		//sprite_helper();
		if ( time() && 1) vsync();
		swap_screen();
		set_sprite(0,pl->x,pl->y,pl->anim_frame); // !!
		
	}
}
void show_intro()
{
	u8 a;
	sprites_stop();
	color_key(4);
	pcharmask=1;
	fade_to_black();
	lastmus=musintro;
	music_play(musintro);
	inintro(PAL_INTRO1,IMG_INTRO1,"Планета Паллада системы Сигма 5.");
	inintro(PAL_INTRO2,IMG_INTRO2,"Земная колония ВР-12:Деметра.");
	inintro(PAL_INTRO3,IMG_INTRO3,"19:21 по местному времени.");
	inintro(PAL_INTRO4,IMG_INTRO4,"");
	inintro(PAL_INTRO5,IMG_INTRO5,"");
	inintro(PAL_INTRO6,IMG_INTRO6,"");
	inintro(PAL_INTRO7,IMG_INTRO7,"Орбитальная станция Гефест.");
	inintro(PAL_INTRO_8,IMG_INTRO_8,"Проект Р.О.Б.О.");
	clear_screen(0);
	swap_screen();
	clear_screen(0);
	fade_from_black();
	for(a=0;a<8;a++)
	{
		sfx_play(SFX_SIREN,7);
		pal_select(PAL_INTRO90);
		draw_image(12,4,IMG_INTRO90);
		swap_screen();
		delay(2);
		pal_select(PAL_INTRO91);
		draw_image(12,4,IMG_INTRO91);
		swap_screen();
		delay(2);
		pal_select(PAL_INTRO92);
		draw_image(12,4,IMG_INTRO92);
		swap_screen();
		delay(2);
		pal_select(PAL_INTRO93);
		draw_image(12,4,IMG_INTRO93);
		swap_screen();
		delay(2);
		pal_select(PAL_INTRO94);
		draw_image(12,4,IMG_INTRO94);
		swap_screen();
		delay(2);
	}
	sprites_start();
	clear_screen(0);
	pal_select(PAL_INTRO10);
	swap_screen();
	clear_screen(0);
	swap_screen();
	delay(16);
	inintro2(1,"UAC inc. Hardware testing",22);
	inintro2(2,"ROM Ok",22);
	inintro2(3,"RAM Ok",22);
	inintro2(4,"Battery Ok",22);
	inintro2(5,"Transporting system Ok",22);
	inintro2(6,"Loading drivers",22);
	inintro2(7,"15%",22);
	inintro2(8,"75%",22);
	inintro2(9,"100%",22);
	delay(64);
	draw_image(0,0,IMG_INTRO10);
	inintro2(1,"OS Loading Ok",32);
	inintro2(2,"Language pack loading Ok",32);
	inintro2(3,"Получаю сообщение...",64);
	inintro2(4,"Новое задание",64);
	draw_image(28,0,IMG_MASTER_MIND2);
	draw_image(28,12,IMG_MASTER_MIND);
	inintro2(5,"Цель: Найти и уничтожить",64);
	inintro2(6,"Имя: Надмозг",64);
	inintro2(7,"Место:Лаборатория Стикс",64);
	draw_image(0,0,IMG_INTRO10);
	swap_screen();
	output_x=2;
	output_y=0;
	put_str("Описание: В результате несчастного   случая из под контроля вышел         исследуемый образец N27-Надмозг.     Образец подключился к центральному   компьютеру и подчинил себе все       системы лаборатрории. Внимание!      Начато производство неизвестных      сущностей. Ваша цель: Уничтожить     образец N27 и очистить лаборатории   от присутствия вредоносных субъектов Немедленно приступить к выполнению.");
	swap_screen();
	delay(1024);
	sprites_stop();
	fade_to_black();
	
	pal_select(PAL_INTRO11_1);
	draw_image(0,0,IMG_INTRO11_1);
	swap_screen();
	fade_from_black();
	delay(32);
	pal_select(PAL_INTRO11_2);
	draw_image(0,0,IMG_INTRO11_2);
	swap_screen();
	delay(32);
	pal_select(PAL_INTRO11_3);
	draw_image(0,0,IMG_INTRO11_3);
	swap_screen();
	delay(32);
	pal_select(PAL_INTRO11_4);
	draw_image(0,0,IMG_INTRO11_4);
	swap_screen();
	delay(32);

	sprites_start();
	fade_from_black();
	pcharmask=0;
}
void in_main_menu()
{
	u8 tr,a,b,flg,curpos,cntsym;
	u8 *dif_names[]={"Очень легко","Легко","Почти норма","Норма","Чуть сложнее","Сложно","Настоящее испытание"};
	u8 bufpass[5];
	u8 str[4];
	int joy=joystick();
	tr=1;
	clear_screen(0);
	sprites_stop();
	swap_screen();
	for(a=1;a<64;a++)
	{
		spritenums[a]=0;
		set_sprite(a,0,0,3);
	}
	//swap_screen();
	
	pal_select(PAL_MAIN4);
	draw_image(0,0,IMG_MAIN0);
	swap_screen();
	fade_from_black();
	draw_image(0,0,IMG_MAIN1);
	swap_screen();
	draw_image(0,0,IMG_MAIN2);
	swap_screen();
	draw_image(0,0,IMG_MAIN3);
	swap_screen();
	draw_image(0,0,IMG_MAIN4);
	swap_screen();
	draw_image(0,0,IMG_MAIN4);
	swap_screen();
	sprites_start();
	output_x=12;
	output_y=4;
	put_str("ПРОЕКТ Р.О.Б.О.");
	output_x=11;
	output_y=5;
	put_str("________________");
	
	output_x=9;
	output_y=8;
	put_str("Новая игра");
	output_x=9;
	output_y=10;
	put_str("Ввод пароля");
	output_x=9;
	output_y=12;
	put_str("Просмотр интро");
	output_x=9;
	output_y=14;
	put_str("Инструкции");
	output_x=9;
	output_y=16;
	put_str("Выбор сложности");
	output_x=9;
	output_y=18;
	put_str("(");
	put_str(dif_names[curdif]);
	put_str("}");
	
	curpos=0;
	
	while(tr)
	{
		rand16();
		keyboard(keys);
		joy=joystick();
		if(keys[KEY_Q]==KEY_DOWN)
		{	
			//show_outro();

		}
		if(keys[KEY_ENTER]==KEY_DOWN)
		{
			if(curpos==0)	
			{
				tr=0;
				pldead=1;
				ingame=1;
			}
			if(curpos==1)
			{
				sfx_play(SFX_MENU,7);
				output_x=10;
				output_y=20;
				put_str("Пароль:");
				swap_screen();
				cntsym=0;
				delay(15);
				while(cntsym<5)
				{
					keyboard(keys);
					for(a=1;a<40;a++)
					{
						if(keys[a]==KEY_DOWN)
						{

							bufpass[cntsym]=code_to_char[a];
							put_char(bufpass[cntsym]);
							swap_screen();
							output_x--;
							put_char(bufpass[cntsym]);
							swap_screen();
							sfx_play(SFX_MENU,7);
							delay(12);
							cntsym++;
						}
					}
				}
				
				
				output_x=10;
				output_y=20;
				for(a=0;a<6;a++)
				{
					flg=0;
					if(bufpass[0]==passwords[a][0])
					{
						flg=1;
						for(b=1;b<4;b++)
						{
							if(bufpass[b]!=passwords[a][b])flg=0;
						}
					}
					if(flg==1)
					{
						put_str("                        ");
						maxdif=a+1;
						curdif=maxdif;
						sfx_play(SFX_MENU,7);
						delay(6);
						output_x=9;
						output_y=18;
						put_str("                      ");
						output_x=9;
						output_y=18;
						put_str("(");
						put_str(dif_names[curdif]);
						put_str("}");
						break;
					}
				}
				if(flg==0)
				{
					put_str("                      ");
				}
			}
			
			if(curpos==2) 
			{
				tr=0;
				show_intro();
				
				pldead=0;
				ingame=0;
			}
			if(curpos==4)
			{
				if(curdif<maxdif)curdif++;
				else curdif=0;
				sfx_play(SFX_MENU,7);
				delay(6);
				output_x=9;
				output_y=18;
				put_str("                      ");
				output_x=9;
				output_y=18;
				put_str("(");
				put_str(dif_names[curdif]);
				put_str("}");
			}
			if(curpos==3)
			{	
				tr=0;
				ingame=0;
				pldead=0;
				show_instructions();
			}
			
		}
		if(joy&JOY_LEFT>0&&curpos==4)
		{
			sfx_play(SFX_MENU,7);
			if(curdif>0)curdif--;
			else curdif=maxdif;
							delay(8);
				output_x=9;
				output_y=18;
				put_str("                      ");
				output_x=9;
				output_y=18;
				put_str("(");
				put_str(dif_names[curdif]);
				put_str("}");
		}
		if(joy&JOY_RIGHT>0&&curpos==4)
		{
				if(curdif<maxdif)curdif++;
				else curdif=0;
				sfx_play(SFX_MENU,7);
				delay(6);
				output_x=9;
				output_y=18;
				put_str("                      ");
				output_x=9;
				output_y=18;
				put_str("(");
				put_str(dif_names[curdif]);
				put_str("}");
		}
		if(joy&JOY_UP>0)
		{
			sfx_play(SFX_MENU,7);
			if(curpos>0)curpos--;
			else curpos=4;
			delay(6);
		}
		if(joy&JOY_DOWN>0)
		{
			sfx_play(SFX_MENU,7);
			if(curpos<4)curpos++;
			else curpos=0;
			delay(6);
		}
		set_sprite(0,100,64+curpos*16,35);
		swap_screen();
	}
	
	//sprites_start();
    sprites_stop();
    fade_to_black();
	clear_screen(0);
	swap_screen();
	clear_screen(0);
}
const u8 text[]="                                        Привет!!! Я - Hippiman, сейчас осень 2012 года и это моя новая игра - Project ROBO. А сейчас я представлю людей, без которых она не была бы такой, какой вы ее скоро увидите. Великолепная музыка, которую вы сейчас можете слышать, принадлежит авторству CJ Splinter. А за бета тест отвечал Baxter. Так же хочу сказать спасибо Alone и Shiru. Эти люди создали Sdk в котором разработана эта игра. А чего вы еще ждете? Жмите любую кнопку и приступайте к спасению человечества. Для непонятливых есть подробная инструкция, а для любознательных есть интро. Их вы найдете в главном меню. И еще, один раз пройти игру мало. При каждом прохождении вы будете получать доступ к следующему уровню сложности, на котором  будет больше разновидностей монстров, больше идов комнат и так далее. Любые вопросы по игре можно задавать мне на мыло kein1985@yandex.ru или на форуме zx.pk.ru. Вроде все, удачи!                                        #";
void in_title_screen()
{	
	u8 a,b;
	i16 pos,c,d;
	
	u8 buf[41];
	a=1;
	
	
	fade_to_black();
	border(4);
	sprites_stop();
	lastmus=menumus;
	music_play(menumus);	
	pal_select(PAL_TITLE);
	draw_image(0,0,IMG_TITLE);
	swap_screen();
	draw_image(0,0,IMG_TITLE);
	swap_screen();
	fade_from_black();
	swap_screen();
	for(b=0;b<40;b++)buf[b]=' ';
	buf[39]='\0';
	pos=0;
	while(a)
	{
		output_x=0;
		output_y=24;
		put_str(buf);
		swap_screen();
		pos++;
		for(b=0;b<39;b++)
		{
			if(text[pos+b]!='#')
			{			
				buf[b]=text[pos+b];
			}
			else
			{
				b=39;
				pos=0;
			}
		}
		a=check_a_key();
        for(b=0;b<10;b++)
        {
            delay(1);
            a=check_a_key();
            if(!a) break;
        }   
//		delay(4);
//		a=check_a_key();
//		delay(4);
//		a=check_a_key();
//		delay(2);
//		a=check_a_key();
		buf[40]='\0';
		//a=check_a_key();
	}
		fade_to_black();
//		sprites_start();
}
void main(void)
{
	int a,x,y,joy;
	char buf[16];
	Player player;

	//---------------------------

	pldead=1;
	curdif=0;
	maxdif=0;
	//show_intro();
	bonus_variant=def_bonus_variant;
	while(1)
	{	
		in_title_screen();
		border(0);
		in_main_menu();
		curlevel=1;
		on_level_points=dif_start_mon_points[curdif];
		player.pwr=5;
		//player.pwr=50;
		
		
		player.shoot_spd=20;
		player.shoot_delay=0;
		player.bullifetime=10;

		player.health=dif_start_health[curdif];
		player.damaged=0;
		player.coins=0;
		player.speed=2;
		player.bulspeed=3;
		is_final_battle=0;
		prespath=0;
		lvwalk=0;
		player.bonuses[0]=player.bonuses[1]=player.bonuses[2]=player.bonuses[3]=32;
		
		
	//music_play(MUS_LEVEL);
	//sfx_play(SFX_FIRE,8);
		
		while (pldead)
		{
			//music_play(MUS_ROBO4);
			player.old_bullifetime=player.bullifetime;
			player.old_pwr=player.pwr;
			player.old_shoot_spd=player.shoot_spd;
			player.old_speed=player.speed;
			//pal_select(PAL_TILES);
			
			pdx=0;
			pdy=0;
			count_enemys=0;
			only_redraw=0;
			sprites_start();
			
			player.y=128;
			player.x=64;
		
			//bullets mass clear
			for(a=0;a<32;a++)
			{
				bullets[a].isfree=1;
			}
			//sprites mass clear
			for(a=0;a<64;a++)
			{
				spritenums[a]=0;
			}
			
			spritenums[0]=1;//player
			
			//---------------------------
			
			
			for(a=0;a<16;a++)enemys[a].dead=1;
			
			gen_global_map(dif_cnt_start_rooms[curdif]+2*(curlevel));//2
			only_redraw=0;
			player.bullifetime=player.old_bullifetime;
			player.pwr=player.old_pwr;
			player.shoot_spd=player.old_shoot_spd;
			player.speed=player.old_speed;
			//*********************************
			fade_to_black();
            pal_select(PAL_TILES);
			if(curlevel<dif_cnt_levels[curdif])
			{
				sprites_stop();
				draw_map(global_rooms[stroomx][stroomy],1);
				only_redraw=1;
                swap_screen(); // !!
				sprites_start();
				//draw_final_boss_map();
				// !! draw_map(global_rooms[stroomx][stroomy],1);
			}
			else
			{
				is_final_battle=1;
				draw_final_boss_map();
			}
			
			//*********************************
			fade_from_black();
			free_path();
			path_pl(&player);
			currecalc=1;
			opened=0;
			print_pl_health(&player);
			//in_shop(&player);
			//sfx_play(SFX_DAMAGE,8);
			if(sndon==1)sfx_play(SFX_COIN,7);
			in_game(&player);
			if(pldead==1)in_shop(&player);
			
			on_level_points+=dif_mon_add_points[curdif];
			curlevel++;
		}
	}
}
