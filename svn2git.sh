#!/bin/sh -e
# bzflag
# Copyright (c) 1993-2014 Tim Riker
#
# This package is free software;  you can redistribute it and/or
# modify it under the terms of the license found in the file
# named COPYING that should have accompanied this file.
#
# THIS PACKAGE IS PROVIDED ``AS IS'' AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

# Import the BZFlag SourceForge Subversion repository into Git.  The
# complexity of this carefully tailored script mirrors the complexity
# generated by more than 70 people in 13+ years of development.

SOURCE="`dirname $0`"
SOURCE="`readlink -f $SOURCE`"			# use full path
MASTER_REPO="file://`cd $SOURCE && git rev-parse --git-dir`"
AUTHORS="$SOURCE/svn_authors"
UPSTREAM_REPO=https://svn.code.sf.net/p/bzflag/code
UPSTREAM_UUID=08b3d480-bf2c-0410-a26f-811ee3361c24
SVN_REPO=file:///scratch/bzflag/bzflag.svn	# $UPSTREAM_REPO will be much slower
STARTING_REVISION=1	# default
ENDING_REVISION=22835	# default, takes 3 hours on Bullet Catcher's computer

# There are some deficiencies of git-svn that must be overcome to
# faithfully import the BZFlag Subversion repository into Git.
#
# The first is that git-svn often chooses the wrong parent commit for
# new branches and tags, especially when the parent is in a branch
# rather than on the trunk.  We work around this by stopping the
# import at empirically-determined revisions to rebase a commit onto
# the correct parent and then advancing the relevant branch head to
# include that commit before continuing.
#
# Another is that git-svn does not know how to choose a parent for an
# empty commit (one that makes no changes to the tree), and simply
# bypasses it.  For completeness, we synthesize empty Git commits
# corresponding to the empty Subversion revisions.
#
# Multiple subproject directories in the Subversion "trunk" hierarchy
# are difficult to deal with when a branch of one is copied back to
# trunk.  Working from a database of exceptional commits is the way to
# success.
#
# Note that the use of "awk | xargs git rm" in this script assumes Git
# version 1.8.5 or higher.  With 1.8.4 and lower the $5 awk variable
# must be used when parsing "git status" output.

# parameters:
# 1 Subversion revision number
git_svn_fetch()
{
# ignore trunk files belonging to other repos
git svn fetch -q -r $1 --authors-file=$AUTHORS --ignore-paths=$IGNORE_PATHS
}

GIT_REPO_NAME=svn2git
if [ $# -gt 0 ] ; then
	TARGET_REPO=$1
	shift
	GIT_REPO_NAME="$GIT_REPO_NAME.$TARGET_REPO"
	if [ $# -gt 0 ] ; then
		STARTING_REVISION=$1
		shift
		if [ $# -gt 0 ] ; then
			ENDING_REVISION=$1
			shift
		fi
	fi
fi
cd /tmp		# use a tmpfs (ramdisk) file system for maximum speed
rm -rf $GIT_REPO_NAME
exec < /dev/null > $GIT_REPO_NAME.log 2>&1

git svn init $SVN_REPO --rewrite-root=$UPSTREAM_REPO \
 --stdlayout \
 --branches=branches/experimental \
 --branches=branches \
 --prefix='' \
 $GIT_REPO_NAME
cd $GIT_REPO_NAME
# The git-svn documentation claims that --rewrite-root and
# --rewrite-uuid may be used together, but the "git svn init" code
# prohibits it.  Work around this by adding the corresponding option
# in a separate step.
git config --local svn-remote.svn.rewriteUUID $UPSTREAM_UUID

SAVEIFS="$IFS"
IFS=,
set -x
while read rev repo method branch tag ; do
	case "$rev" in
	    \#*|'')
		;;	# ignore comments and blank lines
	    default)
		DEFAULT_REPO=$repo
		if [ -z "$TARGET_REPO" ] ; then
			TARGET_REPO=$DEFAULT_REPO
		fi
		case $TARGET_REPO in
		    admin)
			IGNORE_PATHS='^trunk/[^a]'
			;;
		    bzauthd)
			IGNORE_PATHS='^trunk/([^b]|..[^a])'
			;;
		    bzedit)
			IGNORE_PATHS='^trunk/([^b]|..[^e]|......[^/])'
			;;
		    bzeditw32)
			IGNORE_PATHS='^trunk/([^b]|..[^e]|....../)'
			;;
		    bzflag)
			IGNORE_PATHS='^trunk/([^b]|..[^f])'
			;;
		    bzstats)
			IGNORE_PATHS='^trunk/([^b]|..[^s])'
			;;
		    bzview)
			IGNORE_PATHS='^trunk/([^b]|..[^v])'
			;;
		    bzwgen)
			IGNORE_PATHS='^trunk/([^b]|...[^g])'
			;;
		    bzworkbench)
			IGNORE_PATHS='^trunk/([^b]|...[^o])'
			;;
		    custom_plugins)
			IGNORE_PATHS='^trunk/[^c]'
			;;
		    db)
			IGNORE_PATHS='^trunk/[^d]'
			;;
		    pybzflag)
			IGNORE_PATHS='^trunk/[^p]'
			;;
		    tools)
			IGNORE_PATHS='^trunk/[^t]'
			;;
		    web)
			IGNORE_PATHS='^trunk/[^w]'
			;;
		    *)
			echo "No such repo '$TARGET_REPO'"
			exit 1
			;;
		esac
		NEXT_REVISION=$STARTING_REVISION
		echo default repo: $DEFAULT_REPO
		echo starting revision: $NEXT_REVISION
		;;
	    *)
		if [ $NEXT_REVISION -lt "$rev" ] ; then
			STOPPING_POINT=`expr $rev - 1`
			if [ $STOPPING_POINT -gt $ENDING_REVISION ] ; then
				STOPPING_POINT=$ENDING_REVISION
			fi
			if [ $NEXT_REVISION -lt $STOPPING_POINT ] ; then
				RANGE=${NEXT_REVISION}:$STOPPING_POINT
			elif [ $NEXT_REVISION -eq $STOPPING_POINT ] ; then
				RANGE=$NEXT_REVISION
			else
#				echo r$rev next revision $NEXT_REVISION must be less than or equal to $STOPPING_POINT
#				exit 1
				continue
			fi
			if [ $TARGET_REPO = $DEFAULT_REPO ] ; then
				git_svn_fetch $RANGE
				NEXT_REVISION=`expr $STOPPING_POINT + 1`
			else
				set +x	# hide lots of noise
				SKIPPED="`seq $NEXT_REVISION $STOPPING_POINT | xargs` $SKIPPED"
				set -x
				NEXT_REVISION=$rev
			fi
		fi
		if [ $NEXT_REVISION -le $ENDING_REVISION -a $NEXT_REVISION -eq "$rev" ] ; then
			if [ "x$repo" = "x$TARGET_REPO" ] ; then
				rm -f .git/COMMIT_EDITMSG .git/MERGE_MSG	# ensure that the wrong message isn't used
				case "$method" in
				    auto)
					git_svn_fetch $rev
					;;
				    empty)
					# Synthesize an empty Git commit from Subversion.
					# Assumes the author has at least one previous commit.
					DATE="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<date>==s and s=</date>.*==s and print'`"
					AUTHOR="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<author>==s and s=</author>.*==s and print'`"
					MESSAGE="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<msg>==s and s=</msg>.*==s and print'`"
					case "$branch" in
					    trunk|tags/*)
						LOCATION=$branch
						;;
					    *)
						LOCATION=branches/$branch
						;;
					esac
					git checkout remotes/$branch
					git commit --allow-empty "--date=$DATE" "--author=$AUTHOR" "-m$MESSAGE

git-svn-id: $UPSTREAM_REPO/$LOCATION@$rev $UPSTREAM_UUID"
					git rev-parse HEAD > .git/refs/remotes/$branch
					if [ $rev -eq 17840 ] ; then
						find .git -name v2_0_12 -exec rename -v 12 12.deleted {} +
					fi
					;;
				    rebase_branch|rebase_branch_inline)	# move branch to correct parent
					new_parent=remotes/$branch
					git rev-parse --verify $new_parent
					if [ -z "$tag" ] ; then
						echo r$rev requires a source branch in the tag field
						exit 1
					fi
					source_branch=remotes/$tag
					git_svn_fetch $rev
					git rev-parse --verify $source_branch
					if git rev-parse --verify ${source_branch}~ ; then
						onto="--onto $new_parent ${source_branch}~"
					else
						onto=$new_parent
					fi
					# extra effort is required to rebase a lone empty commit
					if ! eval git rebase --keep-empty $onto $source_branch ; then
						if [ $rev -eq 21396 ] ; then
							git add bzflag/include/PlayerInfo.h
							if [ -d $repo/src/other ] ; then
								find $repo/src/other -depth -exec rmdir {} +	# only needed for a partial repo
							fi
							sed -i '1,/^git-svn-id:/!d' .git/MERGE_MSG
							git commit --allow-empty -F .git/MERGE_MSG
						else
							git commit --allow-empty -F .git/COMMIT_EDITMSG
						fi
						git cherry-pick --continue
					fi
					git rev-parse HEAD > .git/refs/$source_branch
					if [ $method = rebase_branch_inline ] ; then
						git rev-parse HEAD > .git/refs/$new_parent
					fi
					;;
				    cherry_pick_branch_up|cherry_pick_branch_up_inline|cherry_pick_branch_down_inline)	# move to correct parent with sliding top-level directory
					if [ -z "$tag" ] ; then
						echo r$rev requires a tag or source branch
						exit 1
					fi
					git_svn_fetch $rev
					git rev-parse --verify remotes/$tag
					git checkout remotes/$branch
					git cherry-pick --allow-empty --no-commit remotes/$tag
					if [ $method = cherry_pick_branch_up ] ; then
						git rm -q -r $repo
					else
						git reset HEAD
						if [ $rev -eq 15219 ] ; then
							mv [^b]* b?[^f]* $repo/src/bzrobots
						else
							rm -r $repo
							mkdir .bzFLAG
							mv .[^g]?* * .bzFLAG || true	# don't move the .git directory
							mv .bzFLAG $repo
						fi
						git add --all
					fi
					DATE="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<date>==s and s=</date>.*==s and print'`"
					AUTHOR="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<author>==s and s=</author>.*==s and print'`"
					MESSAGE=.git/MERGE_MSG
					if [ ! -f $MESSAGE ] ; then
						MESSAGE=.git/COMMIT_EDITMSG
						if [ ! -f $MESSAGE ] ; then
							# synthesize the commit message
							svn log --xml -r $rev $SVN_REPO | perl -wle 'undef $/; $_ = <>; s=.*<msg>==s and s=</msg>.*==s and print' > $MESSAGE
							echo "" >> $MESSAGE
							case "$tag" in
							    trunk|tags/*)
								LOCATION=$tag
								;;
							    *)
								LOCATION=branches/$tag
								;;
							esac
							echo "git-svn-id: $UPSTREAM_REPO/$LOCATION@$rev $UPSTREAM_UUID" >> $MESSAGE
						fi
					fi
					git commit --allow-empty "--date=$DATE" "--author=$AUTHOR" -F $MESSAGE
					git rev-parse HEAD > .git/refs/remotes/$tag
					case $method in
					    *_inline)
						git rev-parse HEAD > .git/refs/remotes/$branch
						;;
					esac
					;;
				    rebase_tag_branch|rebase_tag_inline)	# move tag to correct parent
					case "$branch" in
					    :*)
						new_parent=`git rev-parse $branch`
						;;
					    *)
						new_parent=remotes/$branch
						git rev-parse --verify $new_parent
						;;
					esac
					git_svn_fetch $rev
					git rev-parse --verify remotes/tags/$tag
					if git rev-parse --verify remotes/tags/${tag}~ ; then
						onto="--onto $new_parent remotes/tags/${tag}~"
					else
						onto=$new_parent
					fi
					# extra effort is required to rebase a lone empty commit
					if ! eval git rebase --keep-empty $onto remotes/tags/$tag ; then
						if [ $rev -eq 6881 ] ; then
							git status | awk '/added by us|deleted by them/ {print $4}' | xargs git rm
							git rm -r bzflag/include bzflag/src bzflag/win32/VC71
							sed '1,/^git-svn-id:/!d' .git/MERGE_MSG > .git/COMMIT_EDITMSG
						fi
						git commit --allow-empty -F .git/COMMIT_EDITMSG
						git cherry-pick --continue
					fi
					git rev-parse HEAD > .git/refs/remotes/tags/$tag
					if [ $method = rebase_tag_inline ] ; then
						git rev-parse HEAD > .git/refs/remotes/$branch
					fi
					;;
				    rebase_r1586)	# r1586 mostly copies the v1_7 branch onto trunk (r1587 finishes the job)
					git_svn_fetch $rev
					git rebase --keep-empty --onto remotes/tags/v1_7temp remotes/trunk~ remotes/trunk || true
					for file in bzflag/src/platform/MacBZFlag-prefix.h bzflag/src/platform/MacOSX/MacBZFlag-prefix.h ; do
						mv -i ${file}~[0-9a-f]* $file
						rm ${file}~HEAD
					done
					git rm bzflag/data/boxwall.rgb
					git status | awk '/added by us|deleted by them/ {print $4}' | xargs git rm
					git status | awk '/deleted by us|added by them/ {print $4}' | xargs git add
					sed -i '1,/^git-svn-id:/!d' .git/MERGE_MSG
					git commit --allow-empty -F .git/MERGE_MSG
					git cherry-pick --continue
					git rev-parse HEAD > .git/refs/remotes/trunk
					;;
				    inline_tag)	# bring inline an empty branched tag
					git rev-parse --verify remotes/$branch
					if [ -z "$tag" ] ; then
						echo r$rev requires a tag
						exit 1
					fi
					git_svn_fetch $rev
					git rev-parse remotes/tags/$tag > .git/refs/remotes/$branch
					;;
				    merge*)
					case "$tag" in
					    '')
						echo r$rev requires a source branch in the tag field
						exit 1
						;;
					    :*)
						source_branch=`git rev-parse $tag`
						;;
					    *)
						source_branch=remotes/$tag
						git rev-parse --verify $source_branch
						;;
					esac
					if [ $rev -eq 6909 ] ; then	# multi-branch commit in Subversion
						git_svn_fetch $rev	# use "auto" on trunk
					fi
					case "$branch" in
					    :*)
						git checkout $branch
						branch=$tag		# very fragile, but gets the job done
						;;
					    *)
						git checkout remotes/$branch
						;;
					esac
					if [ $rev -eq 6909 ] ; then
						git reset --hard HEAD~	# synthesize a merge on v1_10branch
					fi
					if [ "x$branch" = xtrunk ] ; then
						LOCATION=$branch/$repo
					else
						LOCATION=branches/$branch
					fi
					if ! eval git merge -q `echo $method | sed 's/^merge//'` --no-commit $source_branch ; then
						if [ $rev -ne 22471 ] ; then
							exit 1
						fi
					fi
					EXCEPTIONS=	# none by default
					SUBDIR=$repo/	# the most common case
					# separate list items here with commas to match IFS setting
					case $rev in
					    1587)
						git status | awk '/new file:/ {print $3}' | xargs git rm -f
						EXCEPTIONS=DEVINFO,data/boxwall.rgb,package/win32/runmakedb.dsp
						;;
					    2069)
						EXCEPTIONS=include/Flag.h,src/bzflag/playing.cxx
						;;
					    5654)
						git rm -f $repo/A*
						;;
					    6909)
						svn export -q --force $SVN_REPO/$LOCATION/$repo@$rev $repo				# the nuclear option
						git add $repo
						for file in `git status | awk 'BEGIN{ORS=","} $1 == "modified:" {print $2}'` ; do	# ORS matches IFS
							sed -i -e 's/\$Id: .* \$/$Id$/' -e 's/\$Revision: .* \$/$Revision$/' $file	# unexpand keywords
							git add $file
						done
						;;
					    12017)
						EXCEPTIONS=include/PlayerInfo.h,include/bzfsAPI.h,include/global.h,misc/bzfs.conf,src/bzflag/Player.h,src/bzflag/ScoreboardRenderer.cxx,src/bzfs/bzfs.cxx,src/game/PlayerInfo.cxx
						;;
					    12039)
						EXCEPTIONS=src/bzflag/LocalPlayer.cxx,src/bzfs/bzfs.cxx
						;;
					    12060)
						EXCEPTIONS=src/bzfs/CmdLineOptions.cxx,src/bzfs/GameKeeper.h,src/bzfs/bzfs.cxx
						;;
					    12109)
						EXCEPTIONS=src/bzfs/GameKeeper.h,src/bzfs/bzfs.cxx
						;;
					    12166)
						EXCEPTIONS=include/bzfsAPI.h,plugins/doc/events.html,src/bzadmin/CursesMenu.cxx,src/bzfs/bzfs.cxx
						;;
					    12258)
						EXCEPTIONS=ChangeLog,src/bzadmin/bzadmin.cxx,src/bzflag/BackgroundRenderer.cxx,src/bzflag/BackgroundRenderer.h,src/bzflag/HUDRenderer.cxx,src/bzflag/SceneRenderer.cxx,src/bzflag/ScoreboardRenderer.cxx,src/bzflag/SegmentedShotStrategy.cxx,src/bzflag/ShockWaveStrategy.cxx,src/bzflag/playing.cxx,src/bzfs/CmdLineOptions.cxx,src/bzfs/GameKeeper.h,src/bzfs/bzfs.cxx,src/bzfs/commands.cxx,src/common/AutoCompleter.cxx,src/game/PlayerInfo.cxx
						;;
					    12396)
						EXCEPTIONS=ChangeLog,src/bzfs/bzfs.cxx,src/bzfs/bzfsAPI.cxx,src/bzfs/commands.cxx,src/common/TimeBomb.cxx
						;;
					    12504)
						EXCEPTIONS=ChangeLog,plugins/logDetail/logDetail.cpp,src/bzflag/KeyboardMapMenu.cxx
						;;
					    12688)
						EXCEPTIONS=ChangeLog,README.MacOSX,README.WIN32,configure.ac,data/title.png,include/bzfsAPI.h,package/win32/nsis/Makefile.am,plugins/HoldTheFlag/HoldTheFlag.cpp,src/bzflag/GUIOptionsMenu.cxx,src/bzflag/ScoreboardRenderer.cxx,src/bzflag/ScoreboardRenderer.h,src/bzflag/clientCommands.cxx,src/bzflag/defaultBZDB.cxx,src/bzfs/CmdLineOptions.h,src/bzfs/SpawnPosition.cxx,src/bzfs/bzfs.cxx,src/bzfs/bzfsAPI.cxx,src/bzfs/commands.cxx,src/common/TextChunkManager.cxx,win32/Makefile.am,win32/VC71/bzadmin.vcproj,win32/VC71/bzfs.vcproj
						;;
					    12828)
						EXCEPTIONS=Dev-C++/bzfs.dev,README.DEVC++,README.WIN32,configure.ac,include/TextUtils.h,include/bzfsAPI.h,include/common.h,package/win32/README.win32.html,package/win32/nsis/BZFlag.nsi,package/win32/nsis/Makefile.am,plugins/nagware/CHANGELOG.txt,plugins/nagware/NAGSAMPLE.cfg,plugins/nagware/nagware.cpp,src/bzflag/CommandsImplementation.cxx,src/bzflag/World.cxx,src/bzflag/effectsRenderer.cxx,src/bzflag/effectsRenderer.h,src/bzflag/playing.cxx,src/bzfs/bzfs.cxx,src/bzfs/bzfsAPI.cxx,src/bzfs/commands.cxx,src/geometry/BillboardSceneNode.cxx,src/geometry/BoltSceneNode.cxx,src/mediafile/MediaFile.cxx,win32/VC71/bzadmin.vcproj,win32/VC71/common.vcproj
						;;
					    14329)
						# undo all source changes, keeping it as a merged branch
						git checkout $source_branch
						git merge -q --no-ff --no-commit $branch
						git checkout HEAD -- $repo
						;;
					    14345)
						git rm -f $repo/src/bzrobots/daxxar-was-here
						;;
					    14514)
						EXCEPTIONS=src/other/freetype/builds/unix/ftconfig.in
						SUBDIR=
						;;
					    14666)
						EXCEPTIONS=src/bzflag/HUDRenderer.cxx
						SUBDIR=
						;;
					    14675)
						EXCEPTIONS=src/bzflag/HUDRenderer.cxx,src/bzflag/RadarRenderer.cxx,src/bzflag/bzflag.cxx,src/bzrobots/Makefile.am,src/bzrobots/botplaying.cxx,src/other/freetype/builds/unix/configure
						;;
					    17271)
						EXCEPTIONS=MSVC/VC8/bzflag.sln,include/bzUnicode.h,src/bzflag/HUDuiTypeIn.cxx,src/bzflag/playing.cxx,src/bzfs/bzfs.cxx,src/bzfs/bzfsMessages.h,src/common/ShotUpdate.cxx,src/game/MsgStrings.cxx,src/platform/WinDisplay.cxx,src/platform/WinDisplay.h
						SUBDIR=
						;;
					    17454)
						EXCEPTIONS=MSVC/VC8/bzflag.vcproj,src/bzflag/HUDRenderer.cxx,src/bzflag/Plan.cxx
						SUBDIR=
						;;
					    17473)
						EXCEPTIONS=src/bzflag/ServerLink.h,src/bzfs/bzfs.cxx,src/common/KeyManager.cxx
						SUBDIR=
						;;
					    18073)
						EXCEPTIONS=MSVC/VC8/bzflag.vcproj,package/win32/nsis/DisableCheck.bmp,package/win32/nsis/EnableCheck.bmp,plugins/HoldTheFlag/HoldTheFlag.vcproj,plugins/RogueGenocide/RogueGenocide.vcproj,plugins/SAMPLE_PLUGIN/SAMPLE_PLUGIN.vcproj,plugins/airspawn/airspawn.vcproj,plugins/bzfscron/bzfscron.vc8.sln,plugins/bzfscron/bzfscron.vc8.vcproj,plugins/chathistory/chathistory.vcproj,plugins/chatlog/Makefile.am,plugins/chatlog/chatlog.cpp,plugins/fastmap/Makefile.am,plugins/flagStay/flagStay.vcproj,plugins/killall/killall.vcproj,plugins/koth/koth.vcproj,plugins/logDetail/logDetail.vcproj,plugins/mapchange/Makefile.am,plugins/nagware/nagware.vcproj,plugins/playHistoryTracker/playHistoryTracker.vcproj,plugins/plugin_utils/VC8/plugin_utils.vcproj,plugins/recordmatch/recordmatch.vcproj,plugins/serverControl/serverControl.vcproj,plugins/serverSideBotSample/serverSideBotSample.vcproj,plugins/shockwaveDeath/shockwaveDeath.vcproj,plugins/soundTest/soundTest.vcproj,plugins/teamflagreset/teamflagreset.vcproj,plugins/thiefControl/thiefControl.vcproj,plugins/timedctf/timedctf.vcproj,plugins/torBlock/torBlock.sln,plugins/torBlock/torBlock.vcproj,plugins/unrealCTF/Makefile.am,plugins/weaponArena/weaponArena.vcproj,plugins/webReport/Makefile.am,plugins/webstats/Makefile.am,plugins/webstats/README.txt,plugins/webstats/templates/stats.tmpl,plugins/wwzones/wwzones.vcproj
						SUBDIR=
						;;
					    18282)
						EXCEPTIONS=include/MotionUtils.h,include/SegmentedShotStrategy.h,include/ShotPath.h,include/ShotStrategy.h,src/bzflag/AutoPilot.h,src/bzflag/World.h,src/game/MotionUtils.cxx,src/game/SegmentedShotStrategy.cxx,src/game/ShotPath.cxx,src/game/ShotStrategy.cxx
						SUBDIR=
						;;
					    18333)
						# svn cat fails with "E135000: Inconsistent line ending style" on these files
						# correct plugin_HTTP.cpp MD5=3cfec4dd8bbdb6b4753c2720b41a1356
						# correct plugin_HTTP.h   MD5=be721291b3336256e08d127a35ba1b02
						for file in plugin_HTTP.cpp plugin_HTTP.h ; do
							cp $SOURCE/$file plugins/plugin_utils/$file
							git add plugins/plugin_utils/$file
						done
						EXCEPTIONS=MSVC/VC8/bzflag.vcproj,include/ServerItem.h,src/game/ServerItem.cxx
						SUBDIR=
						;;
					    19840)
						git rm -q -r MSVC/VC8
						git rm -q -f src/ogl/OpenGLContext.cxx src/other/freetype/builds/win32/visualc/freetype_vc8.vcproj src/other/freetype/include/freetype/ftcid.h src/other/freetype/include/freetype/internal/services/svcid.h src/other/freetype/include/freetype/internal/services/svttglyf.h
						EXCEPTIONS=MSVC/build/bzflag.sln,MSVC/build/bzflag.vcproj,MSVC/build/bzfs.sln,include/ServerList.h,plugins/configure.ac,src/bzflag/bzflag.cxx,src/bzfs/ListServerConnection.cxx,src/bzfs/bzfs.cxx,src/common/global.cxx,src/game/ServerList.cxx,src/other/curl/buildconf.bat
						SUBDIR=
						;;
					    19841)
						EXCEPTIONS=src/bzfs/bzfs.cxx
						SUBDIR=
						;;
					    22442)
						git mv web/gamestats/libraries/Qore/tests libraries/Qore
						EXCEPTIONS=config/config.php
						SUBDIR=
						;;
					    22471)
						git rm -q -r views/Qore
						mv web/gamestats/views/qore views
						git add views/qore
						mkdir packs/bzstats/views/qore
						git mv web/gamestats/packs/bzstats/views/qore/error packs/bzstats/views/qore
						git mv web/gamestats/libraries/Qore/qexception.php libraries/Qore
						git mv web/gamestats/packs/bzstats/views/default.html.twig packs/bzstats/views
						git rm -q -r web
						;;
					esac
					for file in $EXCEPTIONS ; do
						# copy the desired file version directly from the Subversion repository
						svn cat $SVN_REPO/$LOCATION/$file@$rev > $SUBDIR$file
						case $file in
						    configure.ac|plugins/HoldTheFlag/HoldTheFlag.cpp|plugins/nagware/nagware.cpp|src/bzflag/ScoreboardRenderer.cxx)
							sed -i -e 's/\$Id: .* \$/$Id$/' -e 's/\$Revision: .* \$/$Revision$/' $SUBDIR$file	# unexpand keywords
							;;
						esac
						git add $SUBDIR$file
					done
					DATE="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<date>==s and s=</date>.*==s and print'`"
					AUTHOR="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<author>==s and s=</author>.*==s and print'`"
					MESSAGE="`svn log --xml -r $rev $SVN_REPO | perl -wle 'undef \$/; \$_ = <>; s=.*<msg>==s and s=</msg>.*==s and print'`"
					git commit --allow-empty "--date=$DATE" "--author=$AUTHOR" "-m$MESSAGE

git-svn-id: $UPSTREAM_REPO/$LOCATION@$rev $UPSTREAM_UUID"
					git rev-parse HEAD > .git/refs/remotes/$branch
					;;
				    *)
					echo "<$rev> <$repo> <$method> (not implemented) <$branch> <$tag>"
					exit 1
					;;
				esac
			else
				echo skipping $repo r$rev
				set +x	# hide lots of noise
				SKIPPED="$rev $SKIPPED"
				set -x
			fi
			NEXT_REVISION=`expr $NEXT_REVISION + 1`
#		else
#			echo "r$rev is out of sequence"
#			exit 1
		fi
		;;
	esac
done < $SOURCE/revision_list
IFS="$SAVEIFS"

# change all committer info to match the author's
COMMITTER_IS_AUTHOR='
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"'

# move files up out of repo name subdirectory
# move files up out of BZStatCollector and irclink subdirectories
# (the file name bzFLAG is known not to conflict with anything)
# "--subdirectory-filter bzflag" removes empty commits and so is unsuitable
TREE_FILTER="
if mv $TARGET_REPO bzFLAG ; then
 mv bzFLAG/.??* bzFLAG/* . || true
 rmdir bzFLAG
 if test -d BZStatCollector ; then
  mv BZStatCollector/* . || true
  rmdir BZStatCollector
 elif test -d irclink ; then
  mv irclink/* . || true
  rmdir irclink
 fi
fi"

# remove bogus CVS: text
MSG_FILTER='perl -0 -wpe s/CVS:.\*//g\;s/\\n\*\(git-svn-id:\)/\\n\\n\$1/'
# show the full Subversion trunk path
TRUNK_SUBDIR=$TARGET_REPO
if [ $TARGET_REPO = tools ] ; then
	TRUNK_SUBDIR=$TRUNK_SUBDIR/BZStatCollector	# not r22327, see below
elif [ $TARGET_REPO = custom_plugins ] ; then
	TRUNK_SUBDIR=$TRUNK_SUBDIR/irclink
fi
MSG_FILTER="$MSG_FILTER\\;s=/trunk\\\@=/trunk/$TRUNK_SUBDIR\\\@="
if [ $TARGET_REPO = tools ] ; then
	MSG_FILTER="$MSG_FILTER\\;s=/BZStatCollector\\\@22327=\\\@22327="
fi

time git filter-branch --env-filter "$COMMITTER_IS_AUTHOR" --tree-filter "$TREE_FILTER" --msg-filter "$MSG_FILTER" -- --all | tr \\r \\n
rm -rf .git/refs/original	# discard old commits saved by filter-branch

if [ $TARGET_REPO = db -a $NEXT_REVISION -gt 22835 ] ; then
	if ! git rebase --keep-empty :/@20270.08b3d480 remotes/gsoc_bzauthd_db ; then
		git commit --allow-empty -F .git/COMMIT_EDITMSG
		git cherry-pick --continue
	fi
	git branch bzauthd_db	# branch is now properly attached
	git branch -d -r gsoc_bzauthd_db
	git filter-branch --env-filter "$COMMITTER_IS_AUTHOR" -- :/@20270.08b3d480..bzauthd_db | tr \\r \\n
	rm -rf .git/refs/original	# discard old commits saved by filter-branch
fi

if [ $TARGET_REPO = bzflag -a $NEXT_REVISION -gt 22835 ] ; then
	# import post-Subversion commits
	git checkout trunk		# be sure to start at the right place
	git branch new_2.5		# temporary non-conflicting branch name
	git remote add -f import3 $HOME/bzflag/bzflag-import-3.git
	PARENT=`git rev-parse ':/tag as 2\.5\.x devel'`~	# match the remote commit
	git cherry-pick ${PARENT}..9a7c1f0c826158f38061f07273a0366f86611531	# Standard string must be static
	git cherry-pick d86e5a6fc01e0e6a59401c791026d4cbb8a90f76		# Added bz_eGameResumeEvent
	git cherry-pick 5ae409e2463570fe6a85a1ab087a657276d86494..74a97722a0037f7c2895ae962d0421e79b27cd36
	git cherry-pick 8a9b04dc3426927de73cad32aee78c16fdc03dd5..df6db8355c4d3c49fc2f541548d51f98e1f290a7
	git cherry-pick c6ee83203e59db813ac0bc4386de813a7deabdf8		# kick the player when...
	git cherry-pick 90aed6511a69b89184bd36fc65a3b1d372afa563..d5e0974158a2c82892ae0e55293abeed9b9da071	# through pull/4/head
	git cherry-pick b58ea230ff8386daa1a0973eebcad190928bb91d..ff9936ef5830941b1339aafe80a7c907a4296eaa	# resume from main branch
	git cherry-pick 6eeb7955dd1484990e887160ad725d67ed7e123e		# filter messages before enter
	git cherry-pick fc578ad7360a5e78a9bf971fd6b1229d09b52404..a528f0f86c803796b70995df40b981837af4758b
	git cherry-pick a819a592e6d4d9bab04a4301d4a98f3f18b5341c..beb7a3f7636e61b3e3bd3c144cee3161c4408c26
	git cherry-pick 39cea10e31fb2fceeb3611116ed8e3ef2b100426..96ef0546a65d0675ccf9325e9718f100ba004557
	git cherry-pick 21102839a13d04764b30bb8b13a79bdde7f0c99a~..73429627edfa029cc232ff0a7e2a9c49eaaaf2ee
	git cherry-pick 499265f08104ed31317e5bdcaf69814532cfc997	# add increment functions for score for convenience
	git cherry-pick eb3446a782f0d0d8c63871accb42875d241373c6..68900dfc2ebc454bd5ae6e082b15d5ddeb979e7c
	git cherry-pick 6a808d4f281a6bacf83221554ec567e80447cbda
	git cherry-pick a7bf2b5d0a038c0e040827422f66ca0b46eed98c..471bc4ca197b3c11776c8c404c4223c93154e26a
	git cherry-pick 0a610186a030ea8d1b07ffa1a62df2faf4b70426
	git cherry-pick b98fcdebc2b1f772ce2ac5967ac77b65bd43b4e7..06795ff4102d62b9e93ab0fe034d29038070ed4a
	git cherry-pick 7d77503938ce6b7309d313f2c9051b77d3894ec3..879bf3e863df7277e8400cd03848fe1d252d317b
	git cherry-pick dc6b5226449a5e9140b89a2b906a239792f68071..import3/v2_4_x # merge is now unnecessary
	git branch new_2.4		# temporary non-conflicting branch name
	git checkout new_2.5
	git cherry-pick ${PARENT}..':/^update version'
	PARENT=`git rev-parse ":/^Bump the BZFS protocol number"`	# do this now to match the remote commit
	# JeffM would have done this if he were actually committing to the 2.4 branch
	GIT_AUTHOR_DATE='1373139800 -0700' GIT_AUTHOR_NAME='Jeffery Myers' GIT_AUTHOR_EMAIL='JeffM2501@gmail.com' git merge -q "-mMerge branch '2.4'" ':/^ingnore more windows temp files'
	git cherry-pick ${PARENT}~..':/^Change the BZFlag version number from 2\.4\.3'
	GIT_AUTHOR_DATE='1376370000 -0700' git merge -q '-mMerge branch 2.4 onto master.' ':/^For observers,'
	GIT_AUTHOR_DATE='1376861008 -0700' git merge -q '-mMerge recent 2.4 changes into master.' ':/^remove files that were not ready'
	git merge -q --no-commit ':/^Revert r22665 and r22666'
	patch -p0 <<EOF
--- ChangeLog~	2013-12-23
+++ ChangeLog	2013-12-23
@@ -1,6 +1,12 @@
 			     BZFlag Release Notes
 			     ====================
 
+BZFlag 2.5.x
+------------
+
+* Apply colorblindness to your own tank and shots - Kyle Mills
+
+
 BZFlag 2.4.3
 ------------
 
EOF
	git add ChangeLog
	git reset src/bzflag/playing.cxx || true
	git checkout src/bzflag/playing.cxx
	git commit --date='1387869736 -0800' '-mMerge branch 2.4 into master, preserving the colorblindness enhancements of r22665 and r22666.'
	GIT_AUTHOR_DATE='1398250503 -0500' GIT_AUTHOR_NAME='Scott Wichser' GIT_AUTHOR_EMAIL='blast007@users.sourceforge.net' git merge -q "-mMerge remote-tracking branch 'origin/2.4' into master" ':/not the world weapon speed'
	git cherry-pick 0c153e15484692415439e9c878131e583561362e..6da0fbab532c26d59941a166b35e2e244091c8ab
	GIT_AUTHOR_DATE='1403373855 -0500' GIT_AUTHOR_NAME='Scott Wichser' GIT_AUTHOR_EMAIL='blast007@users.sourceforge.net' git merge -q "-mMerge remote-tracking branch 'origin/2.4' into master" ':/missing speed value'
	git cherry-pick 8b30db441309bd0b3b8e9aa55ef8aeed87a890c5..0b7e0e4a3c21ae777d91d0c7829770623f369902
	GIT_AUTHOR_DATE='1403605741 -0500' GIT_AUTHOR_NAME='Scott Wichser' GIT_AUTHOR_EMAIL='blast007@users.sourceforge.net' git merge -q "-mMerge remote-tracking branch 'origin/2.4' into master" ':/^Using nullptr requires gcc'
	git cherry-pick 1a4b3bc6acd77690d3f0d7e2d7cacef87ca89475..import3/v2_6_x
	git remote remove import3
	git tag -d `git tag`					# expunge import3 tags

	# simplify branch names
	git branch 2.99 remotes/v2_99continuing && git branch -d -r v2_99continuing
	git branch -m new_2.5 2.5
	git branch -m new_2.4 2.4
#	git branch 2.3 :/@22049.08b3d480
#	git branch 2.1 :/@16236.08b3d480
	git branch 2.0 remotes/v2_0branch && git branch -d -r v2_0branch
#	git branch 1.11 :/@9899.08b3d480
	git branch 1.10 remotes/v1_10branch && git branch -d -r v1_10branch
#	git branch 1.9 :/@4667.08b3d480
	git branch 1.8 remotes/v1_8 && git branch -d -r v1_8
	git branch 1.7 remotes/v1_7 && git branch -d -r v1_7

	# remove obsolete Subversion branches and tags that are not branch tips
	git branch -d -r ftgl gsoc_08_libbzw gsoc_server_listing remove_flag_id tags/V1_10_6 tags/merge-2_0-2_1-1 tags/merge-2_0-2_1-2 tags/merge-2_0-2_1-3 tags/merge-2_0-2_1-4 tags/merge-2_0-2_1-5 tags/merge-2_0-2_1-6 tags/merge-2_0-2_1-7 tags/merge-2_0-2_1-8 tags/merge-2_0-2_1-9 tags/pre-mesh tags/soc-irc tags/v1_11_12 tags/v1_11_14 tags/v1_11_16 tags/v1_7d_6 tags/v1_7d_7 tags/v1_7d_8 tags/v1_7d_9 tags/v1_7temp tags/v1_8abort tags/v1_9_4_Beta tags/v1_9_6_Beta tags/v1_9_7_Beta tags/v1_9_8_Beta tags/v1_9_9_Beta tags/v2_0_10RC3 tags/v2_0_10_RC1 tags/v2_0_10_RC2 tags/v2_0_12.deleted tags/v2_0_4_rc1 tags/v2_0_4_rc4 tags/v2_0_4_rc5 tags/v2_99archive tags/v3_0_alpha1 tags/v3_0_alpha2 || true

	# fix some e-mail addresses and full names
	CANONICAL_AUTHORS='
test $GIT_AUTHOR_EMAIL = josh@savannah.local && export GIT_AUTHOR_EMAIL=josh@joshb.us
test $GIT_AUTHOR_EMAIL = jwmelto@Goliath.local -o $GIT_AUTHOR_EMAIL = jwmelto@comcast.net && export GIT_AUTHOR_EMAIL=jwmelto@users.sourceforge.net
test $GIT_AUTHOR_EMAIL = jeffm2501@gmail.com && export GIT_AUTHOR_EMAIL=JeffM2501@gmail.com
test $GIT_AUTHOR_EMAIL = kongr45gpen@helit.org && export GIT_AUTHOR_EMAIL=electrovesta@gmail.com
test $GIT_AUTHOR_EMAIL = allejo@users.noreply.github.com && export GIT_AUTHOR_EMAIL=allejo@me.com
test $GIT_AUTHOR_EMAIL = allejo@me.com && export GIT_AUTHOR_NAME=allejo'

	# change committer info to match the author's
	git filter-branch --env-filter "$CANONICAL_AUTHORS$COMMITTER_IS_AUTHOR" -- trunk..2.4 trunk..2.5 | tr \\r \\n
	rm -r .git/refs/original	# discard old commits saved by filter-branch

	# multiple passes are required to update commit hashes in commit messages
	A48FC0F=`git rev-parse ':/^Allow players to join the rabbit' | cut -c1-7`
	EC8C0E0=`git rev-parse ':/^Disallow rabbit' | cut -c1-7`
	git filter-branch --msg-filter "sed -e s/a48fc0f/$A48FC0F/ -e s/ec8c0e0/$EC8C0E0/" -- trunk..2.4 trunk..2.5 | tr \\r \\n
	rm -r .git/refs/original	# discard old commits saved by filter-branch

	seven4876F1FAC45A7B4658F00A2C10F231414DC4E2C=`git rev-parse ':/^Undo most of'`
	git filter-branch --msg-filter "sed -e s/74876f1fac45a7b4658f00a2c10f231414dc4e2c/$seven4876F1FAC45A7B4658F00A2C10F231414DC4E2C/" -- trunk..2.4 trunk..2.5 | tr \\r \\n
	rm -r .git/refs/original	# discard old commits saved by filter-branch

	git branch -d master		# discard useless old master branch
	git branch -m 2.5 master	# we choose this method of confusion about which branch to use
	git checkout master		# default branch
else
	git checkout master
	git merge -q --ff-only trunk
fi

# change Subversion tag branches into Git tags
for branch in `git branch -r` ; do
	case $branch in
	    tags/preMeshDrawInfo)
		tag=2.0_preMeshDrawInfo
		;;
	    tags/soc-bz*|tags/v1_6_[45])
		tag=		# no Git tag
		;;
	    tags/v20020226)
		tag=v1.7e5_20020226
		;;
	    tags/*)
		# change underscores to periods appropriately
		tag=`echo $branch | sed -e 's=^tags/==' -e '/^v/s/_/./' -e '/^v[12]\.[0-9][0-9]*_/s/_/./'`
		;;
	    *)
		continue
		;;
	esac
	if [ "x$tag" != x ] ; then
		git tag $tag $branch
	fi
	git branch -d -r $branch
done

# change remaining Subversion branches into local Git branches
for branch in `git branch -a -r` ; do
	case $branch in
	    2_4_OSX_Lion_Rebuild_branch)
		local=2.4_Mac_OS_X_Lion_rebuild
		;;
	    bzflag)
		git tag 1.7_archive_2 $branch
		local=
		;;
	    experimental)
		git branch -D -r $branch		# remove with prejudice
		continue
		;;
	    trepan)
		local=2.99_lua
		;;
	    trunk)
		if [ $NEXT_REVISION -gt 22835 ] ; then
			git branch -d -r $branch	# "trunk" is a Subversion convention
		fi
		continue
		;;
	    v1_7branch)
		git tag 1.7_archive_1 $branch
		local=
		;;
	    v1_10branch)
		if [ $TARGET_REPO != bzflag ] ; then
			git branch -D -r $branch	# sloppy r9311 in db repo
		fi
		continue
		;;
	    v2_0_cs_branch)
		local=2.0_crystal_space
		;;
	    v2_99_net_branch)
		local=2.99_network_rewrite
		;;
	    v2_99_shot_branch)
		local=2.99_server_shot_control
		;;
	    gsoc_collisions)
		local=2.99_server_collisions
		;;
	    gsoc_irc)
		local=2.0_irc
		;;
	    gsoc_*)
		local=`echo $branch | sed 's/^gsoc/2.99/'`
		;;
	    *)
		local=$branch
		;;
	esac
	if [ "x$local" != x ] ; then
		git branch $local remotes/$branch
	fi
	git branch -d -r $branch
done

sleep 1						# let the clock advance
git reflog expire --expire=now --all		# purge reflogs
git gc --prune=now				# rewritten commits be gone!
rm -f .git/COMMIT_EDITMSG .git/FETCH_HEAD	# tidy
rm -r .git/logs/refs/remotes .git/refs/remotes	# tidy
git status --ignored				# update index and show state

set +x	# hide lots of noise
( seq $STARTING_REVISION $ENDING_REVISION
  # these Subversion revisions appear as two Git commits because each changes both trunk and a branch
  if [ $TARGET_REPO = bzflag ] ; then
	for r in 298 722 4194 4195 4197 4198 5793 5794 5943 5997 5998 6006 6007 6008 6084 6130 6162 6170 6171 6204 6455 6456 6459 6492 6654 6706 6789 6909 7461 7462 7468 7587 7828 8480 9311 11953 11974 12096 12102 12103 12104 12205 12355 12362 12450 12523 12524 12529 12550 12653 12797 12801 12803 12815 13008 13053 13152 13226 13247 13300 13328 13581 13585 13653 13654 13655 13656 13660 13664 13665 13667 13679 13680 13706 13782 13801 13842 13913 13915 ; do
		if [ $STARTING_REVISION -le $r -a $r -le $ENDING_REVISION ] ; then
			echo $r
		fi
	done
  fi
) | sort -n > /tmp/$GIT_REPO_NAME.expect
( git log --all | awk '$1 == "git-svn-id:" && $3 == "08b3d480-bf2c-0410-a26f-811ee3361c24" {print substr($2,index($2,"@")+1)}'
  echo -n "$SKIPPED" | tr ' ' \\n
) | sort -n > /tmp/$GIT_REPO_NAME.have
if cmp -s /tmp/$GIT_REPO_NAME.expect /tmp/$GIT_REPO_NAME.have ; then
	echo "All revisions accounted for."
else
	echo "expected vs. actual subversion commits:"
	diff /tmp/$GIT_REPO_NAME.expect /tmp/$GIT_REPO_NAME.have || true
fi
rm /tmp/$GIT_REPO_NAME.expect /tmp/$GIT_REPO_NAME.have

exit 0
# Push this to a new empty repo at GitHub:
git remote add origin git@github.com:BZFlag-Dev/bzflag-import-4.git
git push -u origin master
git push -u origin --all
git push -u origin --tags
# add the new repo to the GitHub "developers" team (JeffM)
# add the new repo at http://n.tkte.ch/BZFlag/ (JeffM)
