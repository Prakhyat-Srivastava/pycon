#!/bin/bash
#
# Given a talks schedule CSV, import the data into PostgreSQL import.

set -e

cat > breaks.csv <<EOF
kind_slug,kind_label,day,start,duration,content_override
sponsor-tutorial,Break,2016-05-28,10:30,30,Sponsor Room 1,
sponsor-tutorial,Lunch,2016-05-28,12:30,60,Sponsor Room 2,
sponsor-tutorial,Lunch,2016-05-29,12:30,60,Sponsor Room 1,
sponsor-tutorial,Lunch,2016-05-29,12:30,60,Sponsor Room 2,
tutorial,Lunch,2016-05-28,12:20,60,Tutorial %,
tutorial,Lunch,2016-05-29,12:20,60,Tutorial %,
tutorial, ,2016-05-29,16:40,80,Tutorial %,
tutorial,plenary,2016-05-29,18:00,180,Tutorial %,Opening Reception
talk,Breakfast,2016-05-30,8:00,60,Session %,
talk,plenary,2016-05-30,9:00,30,Session %,Welcome to PyCon
talk,plenary,2016-05-30,9:30,40,Session %,Keynote — Lorena Barba
talk,Break,2016-05-30,10:10,40,Session %,
talk,Lunch,2016-05-30,12:40,60,Session A,
talk,Lunch,2016-05-30,12:40,60,Session B,
talk,Lunch,2016-05-30,12:55,60,Session C,
talk,Lunch,2016-05-30,12:55,60,Session D,
talk,Lunch,2016-05-30,12:55,60,Session E,
talk,Break,2016-05-30,15:45,30,Session A,
talk,Break,2016-05-30,15:45,30,Session B,
talk,Break,2016-05-30,16:00,30,Session C,
talk,Break,2016-05-30,16:00,30,Session D,
talk,Break,2016-05-30,16:00,30,Session E,
talk,plenary,2016-05-30,17:40,60,Session %,Lightning Talks
talk,Breakfast,2016-05-31,8:00,30,Session %,
talk,plenary,2016-05-31,8:30,30,Session %,Lightning Talks
talk,plenary,2016-05-31,9:00,40,Session %,Python Language — Guido van Rossum
talk,plenary,2016-05-31,9:40,40,Session %,Keynote — Parisa Tabriz
talk,Break,2016-05-31,10:20,30,Session %,
talk,Lunch,2016-05-31,12:40,60,Session A,
talk,Lunch,2016-05-31,12:40,60,Session B,
talk,Lunch,2016-05-31,12:55,60,Session C,
talk,Lunch,2016-05-31,12:55,60,Session D,
talk,Lunch,2016-05-31,12:55,60,Session E,
talk,Break,2016-05-31,15:45,30,Session A,
talk,Break,2016-05-31,15:45,30,Session B,
talk,Break,2016-05-31,16:00,30,Session C,
talk,Break,2016-05-31,16:00,30,Session D,
talk,Break,2016-05-31,16:00,30,Session E,
talk,plenary,2016-05-31,17:40,60,Session %,Lightning Talks
talk,Breakfast,2016-06-01,8:00,30,Session %,
talk,plenary,2016-06-01,8:30,30,Session %,Lightning Talks
talk,plenary,2016-06-01,9:00,20,Session %,Python Software Foundation — Van Lindberg
talk,plenary,2016-06-01,9:20,40,Session %,Keynote — Cris Ewing
talk,Break,2016-06-01,10:00,190,Session %,Poster Session / Job Fair / Lunch — Expo Hall
talk,plenary,2016-06-01,15:10,40,Session %,Keynote — K Lars Lohn
talk,plenary,2016-06-01,15:50,20,Session %,Closing Remarks
talk, ,2016-06-01,16:10,20,Session %,
talk,Break,2016-06-01,16:30,90,Session %,Introduction to Sprints
EOF

psql "${1:-pycon2016}" <<'EOF'

begin;

create temporary table b (
 slot_id serial,
 kind_slug text,
 kind_label text,
 day date,
 start time,
 duration integer,
 room_name text,
 content_override text
);

create temporary table s (
 kind_slug text,
 proposal_id integer,
 day date,
 start time,
 duration integer,
 room_name text
);

\copy b (kind_slug, kind_label, day, start, duration, room_name, content_override) from 'breaks.csv' csv header;
\copy s from 'schedule.csv' csv header;

alter table b add column schedule_id integer;
update b set schedule_id = sss.id
 from symposion_schedule_slotkind ssk
   join symposion_schedule_schedule sss on (ssk.schedule_id = sss.id)
 where b.kind_slug = ssk.label
 ;

alter table s add column schedule_id integer;
update s set schedule_id = sss.id
 from proposals_proposalbase ppb
   join proposals_proposalkind ppk on (ppb.kind_id = ppk.id)
   join symposion_schedule_schedule sss on (ppk.section_id = sss.section_id)
 where s.proposal_id = ppb.id
 ;

delete from symposion_schedule_slotkind;
delete from symposion_schedule_slotroom;
delete from symposion_schedule_room;
delete from symposion_schedule_slot;
delete from symposion_schedule_day;
delete from symposion_schedule_presentation_additional_speakers;
delete from symposion_schedule_presentation;

insert into symposion_schedule_slotkind (label, schedule_id)
 select
   t.kind_label,
   (select sss.id
     from symposion_schedule_schedule sss
      join conference_section cs on (sss.section_id = cs.id)
     where cs.slug = t.kind_slug || 's'
   )
  from (
   select distinct kind_slug, kind_label from b
   union
   select distinct kind_slug, kind_slug from s
  ) t;

insert into symposion_schedule_day (date, schedule_id)
 select distinct day, ss.id
  from s
   join proposals_proposalbase pb on (s.proposal_id = pb.id)
   join proposals_proposalkind pk on (pb.kind_id = pk.id)
   join symposion_schedule_schedule ss on (pk.section_id = ss.section_id)
 ;

insert into symposion_schedule_room (name, "order", schedule_id)
 select distinct room_name, 1, ss.id
  from s
   join proposals_proposalbase pb on (s.proposal_id = pb.id)
   join proposals_proposalkind pk on (pb.kind_id = pk.id)
   join symposion_schedule_schedule ss on (pk.section_id = ss.section_id)
  order by room_name
 ;

update symposion_schedule_room set "order" = id;

insert into symposion_schedule_slot
 (id, start, "end", content_override, day_id, kind_id)
 select
  b.slot_id,
  start,
  start + cast(duration || ' minutes' as interval),
  coalesce(b.content_override, ''),
  (select id from symposion_schedule_day ssd
    where ssd.date = day and ssd.schedule_id = b.schedule_id),
  (select id from symposion_schedule_slotkind ssk
    where label = kind_label and ssk.schedule_id = b.schedule_id)
 from b;

insert into symposion_schedule_slot
 (id, start, "end", content_override, day_id, kind_id)
 select
  proposal_id,
  start,
  start + cast(duration || ' minutes' as interval),
  '',
  (select id from symposion_schedule_day ssd
    where ssd.date = day and ssd.schedule_id = s.schedule_id),
  (select id from symposion_schedule_slotkind where label = kind_slug)
 from s;

insert into symposion_schedule_slotroom (room_id, slot_id)
 select
  ssr.id,
  b.slot_id
 from b
  join symposion_schedule_room ssr on (ssr.name like b.room_name);

insert into symposion_schedule_slotroom (room_id, slot_id)
 select
  (select id from symposion_schedule_room where name = room_name),
  proposal_id
 from s;

insert into symposion_schedule_presentation
  (id, title, description, abstract, cancelled,
   proposal_base_id, section_id, slot_id, speaker_id,
   assets_url, slides_url, video_url)
 select
  pb.id,
  pb.title,
  pb.description,
  pb.abstract,
  false,

  s.proposal_id,
  pk.section_id,
  s.proposal_id,
  pb.speaker_id,

  '',
  '',
  ''
 from s
  join proposals_proposalbase pb on (s.proposal_id = pb.id)
  join proposals_proposalkind pk on (pb.kind_id = pk.id)
 ;

insert into symposion_schedule_presentation
  (id, title, description, abstract, cancelled,
   proposal_base_id, section_id, slot_id, speaker_id,
   assets_url, slides_url, video_url)
 select
  pb.id,
  pb.title,
  pb.description,
  pb.abstract,
  false,

  pb.id,
  (select id from conference_section where slug = 'posters'),
  NULL,
  pb.speaker_id,

  '',
  '',
  ''
 from pycon_pyconposterproposal pp
  join proposals_proposalbase pb on (pp.proposalbase_ptr_id = pb.id)
 where overall_status = 4
  and not cancelled
 ;

insert into symposion_schedule_presentation_additional_speakers
  (presentation_id, speaker_id)
 select
  ssp.id, ppas.speaker_id
 from
  proposals_proposalbase_additional_speakers ppas
  join symposion_schedule_presentation ssp
   on (ppas.proposalbase_id = ssp.proposal_base_id);

commit;

EOF