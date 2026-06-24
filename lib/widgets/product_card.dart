import 'package:flutter/material.dart';
import '../main.dart';
import '../models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final bool showTeamPrice;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showTeamPrice = false,
  });

  @override
  Widget build(BuildContext context) {
    final price = product.singlePrice;
    final promo = product.promoPrice;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // All distinct pack types (skip promoprice — shown separately)
    final packPrices = product.prices
        .where((p) =>
            p.type != 'promoprice' &&
            p.value > 0 &&
            p.packType.isNotEmpty)
        .toList();
    // Remove duplicates by packType
    final seen = <String>{};
    final uniquePacks = packPrices.where((p) => seen.add(p.packType)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 56,
                    height: 72,
                    color: Colors.white,
                    child: Image.network(
                      product.cdnImageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.white,
                        child: const Icon(
                          Icons.wine_bar,
                          size: 24,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.brand,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.stockcode,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[400],
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Show all pack types
                    if (uniquePacks.isNotEmpty)
                      ...uniquePacks.map((pp) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Promo strikethrough
                                if (promo != null &&
                                    promo.packType == pp.packType &&
                                    promo.beforePromotion >
                                        promo.afterPromotion)
                                  Text(
                                    '\$${promo.beforePromotion.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[400],
                                      fontSize: 11,
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Pack type label
                                    Container(
                                      margin:
                                          const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.grey[200],
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        pp.packType == 'Bottle'
                                            ? 'ea'
                                            : pp.packType == 'Case'
                                                ? 'case'
                                                : pp.packType
                                                          .toLowerCase()
                                                          .startsWith('case')
                                                    ? 'case'
                                                    : pp.packType
                                                        .toLowerCase(),
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                    // Price
                                    Text(
                                      '\$${pp.value.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: pp == price ? 17 : 12,
                                        color: promo != null &&
                                                promo.packType ==
                                                    pp.packType
                                            ? (isDark
                                                ? AppColors.memberOffer
                                                : AppColors.memberOfferDark)
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )),
                    // Team discount (on single price)
                    if (showTeamPrice)
                      _buildTeamPrice(price?.value ?? 0, isDark),
                    // Promo badge
                    if (promo != null && promo.message.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.memberOfferBgDark
                              : AppColors.memberOfferBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          promo.message,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.memberOffer
                                : AppColors.memberOfferDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamPrice(double regularPrice, bool isDark) {
    // Use API's actual team/member price — no calculation
    final teamP = product.promoPrice;
    if (teamP == null || !teamP.isMemberOffer || teamP.value <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 1),
        Text(
          '\$${regularPrice.toStringAsFixed(2)}',
          style: TextStyle(
            decoration: TextDecoration.lineThrough,
            color: isDark ? Colors.grey[500] : Colors.grey[400],
            fontSize: 11,
          ),
        ),
        Text(
          '\$${teamP.value.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppColors.spendAndGet,
          ),
        ),
      ],
    );
  }
}
