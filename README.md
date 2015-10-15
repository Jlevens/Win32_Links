# Win32::Links

Make symlinks work portably under Windows.

Microsoft introduced POSIX compliant symlinks from Windows Vista (Nov 2006) and Windows Server 2008 (Feb 2008).

The earlier junctions points are a different beast and support something similar (but different) to symlinks and only for directories.

I have done testing to the point that 'use Win32::Links;' will indeed make code written on linux then work seamlessly -- apart from the -l filetest.

The -l filetest is currently implemented as sub 'is_l' (default name). There appears to be no easy way in standard perl to redirect the -l test to my own code, whereas the triumvirate of symlink, readlink and link can be done easily.

I understand that deep magic involving changing the code generated may allow this (just one more rabbit hole to lose myself in). If someone would like to help with this that would of course be great.

Note that I had to 'cpanm --force Inline::C' on Windows 7 Ultimate and strawberry perl 5.22.0. The install errors appear to be related to the install *process* the actual module is working.

The existing CPAN modules Win32::Symlink and Win32::Hardlink both began life circa 2004 years before Microsoft added the POSIX compliant symlinks used by this code. My tests of Win32::Symlink confirmed that it cannot be used as a seamless replacement. Win32::Hardlink I could not even force install.

The ability to create symlinks and hardlinks is protected under Windows and you will need to add the users groups you need via Group Policy to enable this capability.

To Do
=====

1 Report to Audrey Tang about issues with Win32::Symlink and Win32::Hardlink
1 See if -l test can be made seamless and how far back we can go in perl versions
1 Add some import options :STD :VLN (very long names 32767 chars) and importing 'is_l mk_VLN rm_VLN' subs on demand with rename option.
1 Ensure is a no-op on linux systems (except is_l which will still need to be available -- alas code will still need to be refactored for this to work on both platforms).
1 Create my PAUSE account
1 Work out how to build for CPAN especially getting XS from Inline::C
1 Upload to CPAN
1 I have a crude pure perl version to add to CPAN as well: it uses \`mklink\` and \`DIR\`
