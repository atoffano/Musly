import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/auth_provider.dart';
import '../services/subsonic_service.dart';
import 'settings_sheet.dart';

class UserProfileAvatar extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
  final bool interactive;

  const UserProfileAvatar({
    super.key,
    this.size = 32,
    this.onTap,
    this.showBorder = true,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subsonic = Provider.of<SubsonicService>(context, listen: false);
    final bridgeUrl = subsonic.bridgeUrl ?? '';
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final username = authProvider.config?.username ?? 'Aki';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'A';

    final avatarUrl = bridgeUrl.isNotEmpty ? '$bridgeUrl/api/user/avatar' : '';

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF1DB954), Color(0xFF191414)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: showBorder
              ? Border.all(
                  color: isDark ? Colors.white30 : Colors.black12,
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.44,
            ),
          ),
        ),
      );
    }

    Widget avatarWidget;
    if (avatarUrl.isNotEmpty) {
      avatarWidget = CachedNetworkImage(
        imageUrl: avatarUrl,
        imageBuilder: (context, imageProvider) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
            border: showBorder
                ? Border.all(
                    color: isDark ? Colors.white30 : Colors.black12,
                    width: 1.5,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        placeholder: (context, url) => fallbackAvatar(),
        errorWidget: (context, url, error) => fallbackAvatar(),
      );
    } else {
      avatarWidget = fallbackAvatar();
    }

    if (!interactive) {
      return avatarWidget;
    }

    return Tooltip(
      message: 'Profile & Settings',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap ?? () => showSettingsSheet(context),
          child: avatarWidget,
        ),
      ),
    );
  }
}
