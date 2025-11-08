# Migration Guide: Adopting Reusable Components

This guide provides step-by-step instructions for migrating existing screens to use the new reusable components and error handling system.

## Overview

The migration follows a **gradual approach** - you can adopt components incrementally without breaking existing functionality. This guide covers:

1. **Form Components** - Replacing custom form fields
2. **Button Components** - Standardizing button usage
3. **Error Handling** - Implementing consistent error management
4. **Feedback Components** - Adding user feedback

## Phase 1: Form Components Migration

### Step 1.1: Replace Text Fields

**Before (login_screen.dart lines 302-413):**
```dart
Container(
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    color: isDark ? AppTheme.darkCardColor : AppTheme.backgroundColor,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: isDark ? AppTheme.darkDividerColor : AppTheme.dividerColor,
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppTheme.dividerColor.withValues(alpha: 0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: TextFormField(
    controller: _emailController,
    keyboardType: TextInputType.emailAddress,
    textAlign: _emailController.text.isEmpty
        ? (isHebrew ? TextAlign.right : TextAlign.left)
        : TextAlign.left,
    textDirection: _emailController.text.isEmpty
        ? (isHebrew ? TextDirection.rtl : TextDirection.ltr)
        : TextDirection.ltr,
    style: TextStyle(
      color: mainTextColor,
      fontWeight: FontWeight.w300,
    ),
    onChanged: (value) => setState(() {}),
    decoration: InputDecoration(
      hintText: AppTranslations.getText(ref, 'email_hint'),
      hintStyle: TextStyle(
        color: mainTextColor,
        fontWeight: FontWeight.w300,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SvgPicture.asset(
          'assets/images/email.svg',
          width: 18,
          height: 18,
          colorFilter: const ColorFilter.mode(
            AppTheme.textColor,
            BlendMode.srcIn,
          ),
        ),
      ),
      // ... 20+ more lines of decoration
    ),
    validator: (value) {
      if (value == null || value.isEmpty) {
        return AppTranslations.getText(ref, 'email_required');
      }
      if (!Helpers.isValidEmail(value)) {
        return AppTranslations.getText(ref, 'invalid_email');
      }
      return null;
    },
  ),
)
```

**After:**
```dart
AppFormContainer(
  child: AppTextField(
    controller: _emailController,
    hintText: AppTranslations.getText(ref, 'email_hint'),
    prefixSvgAsset: 'assets/images/email.svg',
    keyboardType: TextInputType.emailAddress,
    validator: (value) {
      if (value == null || value.isEmpty) {
        return AppTranslations.getText(ref, 'email_required');
      }
      if (!Helpers.isValidEmail(value)) {
        return AppTranslations.getText(ref, 'invalid_email');
      }
      return null;
    },
  ),
)
```

**Benefits:**
- **Reduced code**: From ~50 lines to ~10 lines
- **Automatic RTL**: No manual text direction handling
- **Theme support**: Automatic light/dark theme adaptation
- **Consistency**: Same styling across all forms

### Step 1.2: Replace Password Fields

**Before (register_screen.dart lines 500-644):**
```dart
Container(
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    // ... 20+ lines of decoration
  ),
  child: TextFormField(
    controller: _passwordController,
    obscureText: !_isPasswordVisible,
    // ... 40+ lines of configuration
    suffixIcon: IconButton(
      icon: Icon(
        _isPasswordVisible
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        color: mainTextColor,
        size: 18,
      ),
      onPressed: () {
        setState(() {
          _isPasswordVisible = !_isPasswordVisible;
        });
      },
    ),
    // ... more configuration
  ),
)
```

**After:**
```dart
AppFormContainer(
  child: AppPasswordField(
    controller: _passwordController,
    hintText: AppTranslations.getText(ref, 'password_hint'),
    validator: (value) {
      if (value == null || value.isEmpty) {
        return AppTranslations.getText(ref, 'password_required');
      }
      return PasswordValidator.validatePassword(value) != null
          ? AppTranslations.getText(ref, PasswordValidator.validatePassword(value)!)
          : null;
    },
  ),
)
```

**Benefits:**
- **Built-in visibility toggle**: No manual state management
- **Password strength**: Optional strength indicator
- **Consistent styling**: Matches other form fields

## Phase 2: Button Components Migration

### Step 2.1: Replace Primary Buttons

**Before (login_screen.dart lines 600-632):**
```dart
SizedBox(
  height: 44,
  child: ElevatedButton(
    onPressed: _isLoading ? null : _signInWithEmailAndPassword,
    style: ElevatedButton.styleFrom(
      backgroundColor: AppTheme.primaryColor,
      foregroundColor: AppTheme.backgroundColor,
      disabledBackgroundColor: AppTheme.primaryColor,
      disabledForegroundColor: AppTheme.backgroundColor,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      textStyle: const TextStyle(
        fontFamily: AppTheme.primaryFontFamily,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
    ),
    child: Text(
      AppTranslations.getText(ref, 'login_button'),
    ),
  ),
)
```

**After:**
```dart
AppPrimaryButton(
  text: AppTranslations.getText(ref, 'login_button'),
  onPressed: _signInWithEmailAndPassword,
  isLoading: _isLoading,
)
```

**Benefits:**
- **Simplified code**: From ~20 lines to ~4 lines
- **Built-in loading**: Automatic loading state handling
- **Consistent styling**: Same appearance across app

### Step 2.2: Replace Text Buttons

**Before:**
```dart
TextButton(
  onPressed: () => context.go('/register'),
  child: Text(
    AppTranslations.getText(ref, 'register_fun'),
    style: const TextStyle(
      color: AppTheme.primaryColor,
      fontWeight: FontWeight.bold,
      fontFamily: AppTheme.primaryFontFamily,
      fontSize: 14,
    ),
  ),
)
```

**After:**
```dart
AppLinkButton(
  text: AppTranslations.getText(ref, 'register_fun'),
  onPressed: () => context.go('/register'),
)
```

## Phase 3: Error Handling Migration

### Step 3.1: Replace Error Display

**Before (login_screen.dart lines 539-574):**
```dart
if (_errorMessage != null) ...[
  const SizedBox(height: 8),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.errorColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: AppTheme.errorColor.withValues(alpha: 0.3),
      ),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline,
          color: AppTheme.errorColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMessage!,
            style: const TextStyle(
              color: AppTheme.errorColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  ),
]
```

**After:**
```dart
if (_errorMessage != null)
  AppErrorContainer(
    message: _errorMessage!,
    onDismiss: () => setState(() => _errorMessage = null),
  )
```

### Step 3.2: Implement Error Handler Service

**Before:**
```dart
try {
  await ref.read(authProvider.notifier).signInWithEmailAndPassword(email, password);
} catch (e) {
  setState(() {
    _errorMessage = e.toString().replaceFirst('Exception: ', '');
    _isLoading = false;
  });
}
```

**After:**
```dart
try {
  await ref.read(authProvider.notifier).signInWithEmailAndPassword(email, password);
} catch (e) {
  final error = ErrorHandlerService.logAndHandleError(
    e,
    ref,
    context: 'Sign in',
    type: ErrorType.auth,
  );
  setState(() {
    _errorMessage = error.userMessage;
    _isLoading = false;
  });
}
```

### Step 3.3: Replace SnackBar Usage

**Before:**
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      AppTranslations.getText(ref, 'item_added_to_list'),
      textAlign: TextAlign.right,
      style: const TextStyle(fontFamily: AppTheme.primaryFontFamily),
    ),
    backgroundColor: AppTheme.primaryColor,
    duration: const Duration(seconds: 2),
  ),
);
```

**After:**
```dart
AppSnackbar.showSuccess(
  context,
  AppTranslations.getText(ref, 'item_added_to_list'),
);
```

## Phase 4: Loading States Migration

### Step 4.1: Replace Loading Indicators

**Before:**
```dart
const Center(
  child: CircularProgressIndicator(
    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
  ),
)
```

**After:**
```dart
const Center(
  child: AppLoadingIndicator(
    message: 'Loading...',
    showMessage: true,
  ),
)
```

### Step 4.2: Replace Empty States

**Before (edit_recipe_screen.dart lines 42-60):**
```dart
Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        Icons.restaurant_menu,
        size: 80,
        color: AppTheme.secondaryTextColor.withValues(alpha: 0.5),
      ),
      const SizedBox(height: 16),
      Text(
        AppTranslations.getText(ref, 'recipe_not_found'),
        style: const TextStyle(
          fontFamily: AppTheme.secondaryFontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: AppTheme.textColor,
        ),
      ),
    ],
  ),
)
```

**After:**
```dart
AppNotFoundState(
  title: AppTranslations.getText(ref, 'recipe_not_found'),
  action: ElevatedButton(
    onPressed: () => context.go('/home'),
    child: Text(AppTranslations.getText(ref, 'go_home')),
  ),
)
```

## Migration Checklist

### For Each Screen:

- [ ] **Identify form fields** that can use `AppTextField` or `AppPasswordField`
- [ ] **Replace custom containers** with `AppFormContainer`
- [ ] **Update buttons** to use `AppPrimaryButton` or `AppTextButton` variants
- [ ] **Replace error displays** with `AppErrorContainer`
- [ ] **Update loading states** to use `AppLoadingIndicator`
- [ ] **Replace empty states** with `AppEmptyState` variants
- [ ] **Implement error handling** using `ErrorHandlerService`
- [ ] **Update SnackBar usage** to use `AppSnackbar` helpers
- [ ] **Test both themes** (light/dark)
- [ ] **Test RTL support** (Hebrew/English)
- [ ] **Remove unused imports** and clean up code

### Priority Order:

1. **High Impact**: Login/Register screens (most duplicated code)
2. **Medium Impact**: Form-heavy screens (recipe creation, profile editing)
3. **Low Impact**: Display screens (recipe detail, profile view)

## Common Pitfalls

### 1. **Don't mix old and new patterns**
```dart
// ❌ Don't do this
AppTextField(
  controller: _controller,
  decoration: InputDecoration(...), // This will be ignored
)

// ✅ Do this instead
AppTextField(
  controller: _controller,
  hintText: 'Enter text',
)
```

### 2. **Handle RTL properly**
```dart
// ❌ Don't manually handle RTL
textAlign: isHebrew ? TextAlign.right : TextAlign.left,

// ✅ Let components handle it automatically
AppTextField(
  controller: _controller,
  // RTL is handled automatically
)
```

### 3. **Use appropriate error handling**
```dart
// ❌ Don't use generic error handling for specific errors
final error = ErrorHandlerService.handleGenericError(e, ref);

// ✅ Use specific error handling
final error = ErrorHandlerService.handleAuthError(e, ref);
```

## Testing After Migration

### 1. **Visual Testing**
- [ ] Light theme appearance
- [ ] Dark theme appearance
- [ ] RTL layout (Hebrew)
- [ ] LTR layout (English)

### 2. **Functional Testing**
- [ ] Form validation works
- [ ] Error states display correctly
- [ ] Loading states show/hide properly
- [ ] Button interactions work
- [ ] Navigation functions correctly

### 3. **Error Testing**
- [ ] Network errors display user-friendly messages
- [ ] Validation errors show appropriate feedback
- [ ] Critical errors show retry options

## Performance Considerations

### 1. **Component Reuse**
- Components are designed to be lightweight
- No performance impact from using components vs custom widgets
- Better performance due to consistent styling (no rebuilds from theme changes)

### 2. **Memory Usage**
- Components dispose of resources properly
- No memory leaks from improper state management
- Reduced memory usage due to code reuse

## Rollback Plan

If issues arise during migration:

1. **Keep old code commented** during initial migration
2. **Test thoroughly** before removing old code
3. **Migrate incrementally** - one screen at a time
4. **Use feature flags** if needed for gradual rollout

## Support

For questions or issues during migration:

1. **Check component documentation** in `lib/widgets/README.md`
2. **Review usage examples** in the documentation
3. **Test with both themes** to ensure compatibility
4. **Verify RTL support** for international users

## Next Steps

After completing migration:

1. **Update new screens** to use components from day one
2. **Establish coding standards** for component usage
3. **Create component tests** for regression prevention
4. **Consider additional components** based on usage patterns

