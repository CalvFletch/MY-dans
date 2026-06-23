import 'package:flutter/material.dart';
import '../main.dart';
import '../models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final price = product.singlePrice;
    final promo = product.promoPrice;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    if (promo != null &&
                        promo.beforePromotion > promo.afterPromotion)
                      Text(
                        '\$${promo.beforePromotion.toStringAsFixed(2)}',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      '\$${(price?.value ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: promo != null
                            ? (isDark
                                  ? AppColors.memberOffer
                                  : AppColors.memberOfferDark)
                            : null,
                      ),
                    ),
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
}
