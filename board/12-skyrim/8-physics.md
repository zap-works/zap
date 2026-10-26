---
size: XL
---
# Physics (milestone 12)

- [ ] Not read (approximated): the solver's own term in the contact's allowance (taken as none); the
  velocity stabilization's table (the skeletons' byte 48, 1.067, for every ragdoll ball and socket;
  the NIF constraints', not read, take none) and why a hung rabbit's swing lasts (about half is
  left after 20 s; the old stable socket damped it to rest in 15 s); the stabilized ball socket (the
  skeletons do not use it; a NIF constraint built at run time might); the prismatic's rows (the lin
  atoms); the motors; the order a world's constraints are turned into rows (the joints', in the
  world's order, after the contacts); the twist limit's softness (tau 0.6 times 0.8 times the
  squared half length of the twist axes' sum: Orgnar's loaded shoulder rests 14 degrees past its
  twist limit, unchecked against the game); restitution (Box2D's relax pass above 1 m/s); rolling
  friction (none: every rolling friction multiplier of the inn's clutter is 0); the island
  deactivation's checks after the counts. Restitution, the lin constraint atoms and the motors are
  Havok's own code, reached from the `hkp*ConstraintData` vtables in the "Havok (the physics)"
  classes section of `reference/exe/README.md`; the collision filter and the angular constraint
  schemas are read.
- [ ] The two CLOUDTRAP/PORTAL and CLOUDTRAP/ACOUSTIC SPACE bits of the layer matrix, cleared through a
  temporary the parser skipped (the "Havok: the collision filter" section).
