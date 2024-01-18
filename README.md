# LZW (TIFF) decoder

**prototype**:

`size_t lzw_decode(const uint8_t *in, size_t in_size, uint8_t *restrict out, size_t out_size);`

**returned value**:
number of decoded bytes or -1 in case of an error
