import 'package:flutter/material.dart';
import 'package:recipe_keeper/widgets/settings_panel.dart';

class AppHeader extends StatelessWidget {
  final String? title;
  final Widget? customContent;
  final VoidCallback? onProfileTap;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  const AppHeader({
    super.key,
    this.title,
    this.customContent,
    this.onProfileTap,
    this.showBackButton = false,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: Container(
        color: const Color(0xFFFF7E6B),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top bar with centered SpoonIt logo and right-aligned user icon
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: Stack(
                    children: [
                      // Back button on the left (if showBackButton is true)
                      if (showBackButton)
                        Positioned(
                          left: 0,
                          top: 2,
                          child: InkWell(
                            onTap:
                                onBackPressed ??
                                () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      const Center(
                        child: Text(
                          'SpoonIt',
                          style: TextStyle(
                            fontFamily: 'Satisfy',
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 2,
                        child: InkWell(
                          onTap:
                              onProfileTap ?? () => showSettingsPanel(context),
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.person_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Custom content (like search bar) or title
                if (customContent != null)
                  customContent!
                else if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Heebo',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
