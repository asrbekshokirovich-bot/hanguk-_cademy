-- Every stroke and every eraser mark failed to save, always, from the very
-- first one drawn.
--
-- `color` was declared `integer` — Postgres's four-byte SIGNED type, which
-- tops out at 2147483647. `Color.toARGB32()` hands back an UNSIGNED 32-bit
-- number, and every colour on the board's own palette carries alpha 0xFF —
-- full opacity, the top byte already past 0xFF000000 — so its ARGB32 value
-- is *always* above 2147483647. The very first pen colour offered,
-- `Color(0xFFF2F5FF)`, is 4294112767: past the ceiling by two billion.
-- There was no partial failure to notice in testing — every insert this
-- table could ever receive was rejected, which is exactly why it surfaced
-- immediately for real and not once in eleven checks against a harness that
-- exercised the policies but never sent a real opaque colour through them.
--
-- Fixed by widening the column, not by narrowing the colour: `bigint` holds
-- the full unsigned 32-bit range with room to spare, and nothing else in the
-- table — the CHECK constraint only tests `color is not null`, the policies
-- never look at it — cares what width the column is.
alter table ol_board_strokes
  alter column color type bigint;
