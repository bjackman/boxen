<div class="marquee-container">
  <h1 class="marquee-content">Welcome to my web site!!!</h1>
</div>

This is all running on Raspberry Pi and an old laptop that I removed the
batteries from and stuffed behind my cupboard.

This tangled pile of cables and plastic behind the cupboard is called THE
HOMELAB.

You can use the homelab to back stuff up if you like, the simplest way to do
that is using [FileBrowser](#filebrowser). If you upload data to the homelab, it
won't be encrypted (unless you encrypt it yourself). At some point, I might need
to poke around trying to fix something I broke, and at that point I might see
the data you've uploaded.

In principle, nobody else should be able to get at the data you upload, but this
is not the most secure thing in the world, you probably don't want to back your
password manager up here (unless it's encrypted).

# Your account on the homelab

Your account is hard-coded. You might find buttons that seem like they will let
you change your password or something, but they won't work (they might actually
break stuff). If you lose your password let me know and I'll make you a new one.

Please don't share your account with anyone.

# Jellyfin

[Jellyfin](https://jellyfin.home.yawn.io) is a media player, there is some media
there. You will need to click the "Sign in with SSO" button at the bottom, the
actual User and Password fields are just there to make life difficult for you.

The "Quick Connect" thing, in theory, lets you sign in from a smart TV or a
Chromecast or something. To do that you first log in on a proper computer, then
you install the Jellyfin client on your TV or whatever, then you press the Quick
Connect button on the TV and it will ask for a code. Then, on your laptop where
you have logged in, you can find a code in your user settings and then type that
code into the TV to log in from the TV.

# FileBrowser

[FileBrowser](https://filebrowser.home.yawn.io/) lets you upload and download
files. You can back stuff up there. It will be stored in my flat.

# SFTP (nerd shit)

There is also an SFTP server that you can use for more automated backups. This
won't be enabled for your account unless you request it though - just let me
know if that's useful to you.

# RSS Reader

There is an RSS reader at https://miniflux.home.yawn.io. An RSS reader lets you
subscribe to blogs and stuff without needing an account on whatever website they
are hosted on.

Click the `+` icon next to "Feeds" in the homepage, then paste in the URL of a
blog you want to subscribe to and hit "find a feed" to subscribe to it.

For Substack blogs, you need to paste the URL that looks like
https://blah.substack.com, not the one that looks like
https://substack.com/@blah.

You can do a bunch of other stuff with RSS too, but this is all I've ever used
it for. [Here's a Reddit comment with some examples, that I found just now by
Googling "stuff you can do with
RSS"](https://www.reddit.com/r/rss/comments/1fb4j4u/comment/lly8ofv/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button).
