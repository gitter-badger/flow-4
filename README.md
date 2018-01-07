* [Overview](doc/overview.md)
* [Basics](doc/basics.md)
* [Entities](doc/entities.md)
* [Introduction](doc/introduction.md)
* [Credits](doc/credits.md)
* [Howto file a bug](doc/howto_bug.md)

newest rework progress please see https://github.com/RalphBariz/causal.git

The whole project is licenced by [GNU Affero General Public License, Verison 3.0](https://github.com/RalphBariz/FLOW/blob/master/LICENSE) [Please read the notes in LICENCE file.]

**BUILD:**
Linux only
* For Debian and derivates please see http://d-apt.sourceforge.net/ and install `sudo apt-get install dmd-bin`
* For Arch Linux and derivates `pacman -S dmd`
* `git clone --recursive https://github.com/RalphBariz/flow-rt.git`
* `cd flow-rt`
* `dmd -run make.d build` You could use ldc instead of dmd. Flow is also compiled using given compiler. Instead of build you could rebuild or clean.

**RUN:**
Dependent of the project you built, its binaries are located in a subfolder *bin* or *lib*
