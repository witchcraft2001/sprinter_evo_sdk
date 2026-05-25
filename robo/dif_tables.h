#ifndef __DIF_TABLES
#define __DIF_TABLES
static u8 curdif,maxdif;

static u8 dif_cnt_templates[]={8,14,20,26,28,28,28};
static u8 dif_cnt_levels[]={3,4,5,6,7,8,9};
static u8 dif_cnt_start_rooms[]={6,6,7,8,9,10,11};
static u16 dif_start_mon_points[]={150,155,175,200,225,250,275};
static u8 dif_mon_add_points[]={50,50,40,40,35,35,50};
static u8 dif_start_health[]={50,75,100,125,150,200,255};
static u8 dif_count_mon_in_room[]={2,3,4,5,6,7,8};

static u8 dif_final_count_mon[]={0,3,4,5,6,7,8};
static u16 dif_final_mon_points[]={0,100,150,170,200,250,350};
static u8 dif_final_eye_health[]={50,50,75,75,100,125,150};
static u8 dif_final_eye_power[]={5,10,17,25,30,40,50};
static u8 dif_final_brain_power[]={10,15,35,40,45,55,75};
static u8 dif_final_brain_delay[]={35,20,15,10,10,5,5};
static u16 dif_final_brain_health[]={150,350,450,550,650,750,1500};
#endif