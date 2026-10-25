# Showcase

Every image here is real output of `bin/cswap-bend` on generic sample data:
six accounts with `example.test` addresses and fake tokens, from parity
fixture `07-list-six-fresh`. Nothing is mocked up.

## List six accounts

![cswap list showing six sample accounts with 5-hour and 7-day usage](showcase/list-six.png)

Reproduce, from the repository root (bend 2.0.38, python3, ImageMagick):

```
just build
sh docs/showcase/make-screenshots.sh
```

The script seeds a scratch HOME from the fixture with `parity/replay --keep`,
runs `cswap list` against it with `NO_COLOR=1 TZ=UTC`, and renders the text to
`docs/showcase/list-six.png`. The reset times shift with the clock; the
percentages do not.
