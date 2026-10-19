# An uncompressed little-endian TIFF with PlanarConfiguration 2 (one strip per
# band), which tiff::writeTIFF() cannot write. `cube` is [y, x, band] uint16.
write_planar_tiff <- function(path, cube) {
  h <- dim(cube)[1]
  w <- dim(cube)[2]
  nb <- dim(cube)[3]
  con <- file(path, "wb")
  on.exit(close(con))
  w16 <- function(x) writeBin(as.integer(x), con, size = 2, endian = "little")
  w32 <- function(x) writeBin(as.integer(x), con, size = 4, endian = "little")
  n_tags <- 11L
  ifd <- 8L
  bps_at <- ifd + 2L + n_tags * 12L + 4L
  offsets_at <- bps_at + 2L * nb
  counts_at <- offsets_at + 4L * nb
  data_at <- counts_at + 4L * nb
  plane <- w * h * 2L
  writeBin(charToRaw("II"), con)
  w16(42)
  w32(ifd)
  w16(n_tags)
  tag <- function(id, type, count, value) {
    w16(id)
    w16(type)
    w32(count)
    if (type == 3 && count == 1) {
      w16(value)
      w16(0)
    } else {
      w32(value)
    }
  }
  tag(256, 4, 1, w)           # ImageWidth
  tag(257, 4, 1, h)           # ImageLength
  tag(258, 3, nb, bps_at)     # BitsPerSample, 16 per band
  tag(259, 3, 1, 1)           # Compression: none
  tag(262, 3, 1, 1)           # PhotometricInterpretation: black is zero
  tag(273, 4, nb, offsets_at) # StripOffsets, one strip per band
  tag(277, 3, 1, nb)          # SamplesPerPixel
  tag(278, 4, 1, h)           # RowsPerStrip
  tag(279, 4, nb, counts_at)  # StripByteCounts
  tag(284, 3, 1, 2)           # PlanarConfiguration: separate
  tag(338, 3, nb - 1, 0)      # ExtraSamples: unspecified (inline for up to 3 bands)
  w32(0)                      # no next directory
  w16(rep(16, nb))
  w32(data_at + (seq_len(nb) - 1L) * plane)
  w32(rep(plane, nb))
  for (b in seq_len(nb)) w16(as.vector(t(cube[, , b])))
}

# Three uint16 bands whose samples encode band, row and column.
planar_cube <- function() {
  cube <- array(0, c(4, 5, 3))
  for (b in 1:3) cube[, , b] <- outer(1:4, 1:5, function(y, x) 100 * b + 10 * y + x)
  cube
}
