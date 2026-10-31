/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/// A tile's size on the Glint home's grid, in cells.
class GlintSize {
  final int width;
  final int height;
  const GlintSize(this.width, this.height);

  static const small = GlintSize(1, 1);
  static const wide = GlintSize(2, 1);
  static const medium = GlintSize(2, 2);
  static const large = GlintSize(3, 2);

  @override
  bool operator ==(Object other) => other is GlintSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => "${width}x$height";
}

/// Where a tile sits: its top-left cell.
class GlintCell {
  final int column;
  final int row;
  const GlintCell(this.column, this.row);

  @override
  bool operator ==(Object other) => other is GlintCell && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);

  @override
  String toString() => "($column, $row)";
}

/// Packs tiles into a fixed number of rows that runs on to the right, as Windows Phone's panorama did: each tile, in
/// order, takes the first place it fits, column by column and top to bottom, so small tiles fill the gaps a big one
/// leaves. A tile taller than the grid is cut to its height.
class GlintLayout {
  final int rows;
  final List<GlintCell> cells;
  final int columns;

  GlintLayout._(this.rows, this.cells, this.columns);

  factory GlintLayout.pack(List<GlintSize> sizes, {int rows = 3}) {
    final taken = <GlintCell>{};
    final placed = <GlintCell>[];
    int columns = 0;
    bool fits(int column, int row, GlintSize size) {
      if (row + size.height > rows) return false;
      for (int c = column; c < column + size.width; c++) {
        for (int r = row; r < row + size.height; r++) {
          if (taken.contains(GlintCell(c, r))) return false;
        }
      }
      return true;
    }

    for (final asked in sizes) {
      final size = GlintSize(asked.width, asked.height.clamp(1, rows));
      GlintCell? at;
      for (int column = 0; at == null; column++) {
        for (int row = 0; row < rows; row++) {
          if (fits(column, row, size)) {
            at = GlintCell(column, row);
            break;
          }
        }
      }
      for (int c = at.column; c < at.column + size.width; c++) {
        for (int r = at.row; r < at.row + size.height; r++) {
          taken.add(GlintCell(c, r));
        }
      }
      placed.add(at);
      if (at.column + size.width > columns) columns = at.column + size.width;
    }
    return GlintLayout._(rows, List.unmodifiable(placed), columns);
  }
}
