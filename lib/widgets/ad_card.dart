import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

class AdCard extends StatelessWidget {
  final Advertisement ad;
  final VoidCallback? onDismiss;
  final VoidCallback? onReport;
  final VoidCallback? onHide;

  const AdCard({
    super.key,
    required this.ad,
    this.onDismiss,
    this.onReport,
    this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clear ADVERTISEMENT label at the top
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ADVERTISEMENT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white54,
                      size: 18,
                    ),
                    color: const Color(0xFF2E244A),
                    onSelected: (value) {
                      switch (value) {
                        case 'report':
                          onReport?.call();
                          break;
                        case 'hide':
                          onHide?.call();
                          break;
                        case 'dismiss':
                          onDismiss?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Text(
                          'Report advertisement',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'hide',
                        child: Text(
                          'Hide this advertisement',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'dismiss',
                        child: Text(
                          'Why am I seeing this?',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Ad image
            Container(
              width: double.infinity,
              height: 200,
              color: const Color(0xFF2E244A),
              child: ad.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: ad.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF2E244A),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFFF4B72),
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFF2E244A),
                        child: const Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 48,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_rounded,
                        size: 48,
                        color: Colors.white38,
                      ),
                    ),
            ),
            // Ad content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ad.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ad.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ad.description,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _handleCta(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4B72),
                        foregroundColor: Colors.white,

                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        ad.ctaText.isNotEmpty ? ad.ctaText : 'Learn More',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Sponsored label at bottom
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sponsored',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCta(BuildContext context) async {
    if (ad.clickAction == 'external_url' && ad.destinationUrl.isNotEmpty) {
      // Validate URL before opening — only allow https
      final uri = Uri.tryParse(ad.destinationUrl);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    }
  }
}

class AdPlaceholderCard extends StatelessWidget {
  const AdPlaceholderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        children: [
          SizedBox(height: 40),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B72)),
          ),
          SizedBox(height: 16),
          Text(
            'Loading advertisement',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}
