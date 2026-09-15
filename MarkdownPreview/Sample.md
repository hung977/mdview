# Markdown Preview Sample

A paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link to Apple](https://www.apple.com).
Soft-wrapped line continues here.  
Hard break above this line.

## Lists

- Unordered one
- Unordered two
  - Nested item
    - Deeper item
- Back to top level

1. First
2. Second
   1. Nested ordered
3. Third

10. Starts at ten
11. Eleven

### Tasks

- [x] Done task
- [ ] Open task
  - [ ] Nested open task

## Quote

> A blockquote with **bold** and a [link](README.md).
>
> > Nested quote.

## Code

Inline `let x = 1` code.

```swift
// A comment
struct Point {
    let x: Double = 1.5   // trailing
    var name = "origin"
}
```

```python
# python comment
def add(a, b):
    return a + b  # 42
```

```
plain block without language
```

## Table

| Option | Type | Description |
|:-------|:----:|------------:|
| `--verbose` | bool | Print more |
| `--out` | path | Where the *output* goes |
| short | x | y |

## Images

![Local image](sample.png)

![Wide image](wide.png)

![Remote badge](https://img.shields.io/badge/build-passing-brightgreen)

![Missing image](does-not-exist.png)

---

Text after a horizontal rule.

<div align="center">raw html block</div>

Last line.
