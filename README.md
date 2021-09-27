# begrudge: convert ANSI-escaped colorized terminal output to classed HTML

`begrudge` is a small tool written in Zig to convert colorized terminal output
that uses [ANSI escape
sequences](https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797) into
class-based HTML snippets. It may be useful for converting the output of tools
such as [`bat`](https://github.com/sharkdp/bat) or
[`glow`](https://github.com/charmbracelet/glow) into something web browsers can
understand, without the need to reinvent or even modify those renderers.

## Getting Started

To my knowledge, `begrudge` is not yet packaged anywhere. You'll need to build
it from source using a Zig 0.8 compiler (newer Zigs, namely the 0.9 nightlies,
may work, but as of yet are untested). The standard `zig build` workflow is
supported. There are no dependencies outside of the standard library.

## Copying, Contributing, and Legal

`begrudge`'s implementation, specification, documentation, artwork, and other
assets are all [Copyfree](http://copyfree.org/), released under the [Creative
Commons Zero 1.0
dedication](https://creativecommons.org/publicdomain/zero/1.0/). This means
you're free to use it for any purpose, in any context, and without letting me
know.

Contributions will be considered, but are not guaranteed to be merged for any
reason or no reason at all. By submitting a contribution to `begrudge`, you assert
the following (this is the [Unlicense waiver](https://unlicense.org/WAIVER)):

> I dedicate any and all copyright interest in this software to the
> public domain. I make this dedication for the benefit of the public at
> large and to the detriment of my heirs and successors. I intend this
> dedication to be an overt act of relinquishment in perpetuity of all
> present and future rights to this software under copyright law.
>
> To the best of my knowledge and belief, my contributions are either
> originally authored by me or are derived from prior works which I have
> verified are also in the public domain and are not subject to claims
> of copyright by other parties.
>
> To the best of my knowledge and belief, no individual, business,
> organization, government, or other entity has any copyright interest
> in my contributions, and I affirm that I will not make contributions
> that are otherwise encumbered.
