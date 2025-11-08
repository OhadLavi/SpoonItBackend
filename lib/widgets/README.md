# Reusable Components Library

This directory contains a collection of reusable UI components designed to provide consistency across the Recipe Keeper app. All components support both light and dark themes, RTL/LTR text direction, and follow the app's design system.

## Directory Structure

```
lib/widgets/
├── forms/           # Form input components
├── buttons/         # Button components
├── feedback/        # Error, loading, and feedback components
└── common/          # General utility components
```

## Form Components

### AppTextField

A unified text field with consistent styling, RTL support, and theme awareness.

**Features:**
- Automatic RTL/LTR text direction handling
- Light/dark theme support
- Prefix icons (SVG and Material icons)
- Optional suffix widgets
- Consistent error styling
- Customizable styling

**Usage:**
```dart
AppTextField(
  controller: _emailController,
  hintText: 'Enter your email',
  prefixSvgAsset: 'assets/images/email.svg',
  keyboardType: TextInputType.emailAddress,
  validator: (value) => value?.isEmpty == true ? 'Required' : null,
)
```

**Props:**
- `controller`: TextEditingController
- `hintText`: Placeholder text
- `prefixSvgAsset`: Path to SVG icon
- `prefixIcon`: Material icon
- `suffix`: Custom suffix widget
- `keyboardType`: Input type
- `validator`: Form validation function
- `onChanged`: Text change callback
- `enabled`: Enable/disable field
- `errorText`: Error message to display

### AppPasswordField

Specialized password field with built-in visibility toggle.

**Features:**
- Extends AppTextField functionality
- Built-in visibility toggle
- Optional password strength indicator
- Custom strength indicator support

**Usage:**
```dart
AppPasswordField(
  controller: _passwordController,
  hintText: 'Enter your password',
  showPasswordStrength: true,
  validator: (value) => value?.length < 6 ? 'Too short' : null,
)
```

### AppFormContainer

Wraps form fields with consistent container styling.

**Features:**
- Consistent border, shadow, and background
- Theme-aware colors
- Customizable styling
- Reduces code duplication

**Usage:**
```dart
AppFormContainer(
  child: AppTextField(
    controller: _emailController,
    hintText: 'Email',
  ),
)
```

## Button Components

### AppPrimaryButton

Primary action button with loading state support.

**Features:**
- Consistent styling (height: 44, borderRadius: 24)
- Built-in loading state
- Disabled state handling
- Theme-aware colors
- Icon support

**Usage:**
```dart
AppPrimaryButton(
  text: 'Sign In',
  onPressed: _signIn,
  isLoading: _isLoading,
  icon: Icons.login,
)
```

**Variants:**
- `AppDangerButton`: For destructive actions
- `AppSuccessButton`: For success actions

### AppTextButton

Secondary/text button with consistent styling.

**Features:**
- Theme-aware colors
- Icon support
- Customizable styling
- Underline support

**Usage:**
```dart
AppTextButton(
  text: 'Forgot Password?',
  onPressed: _resetPassword,
  textColor: AppTheme.primaryColor,
)
```

**Variants:**
- `AppPrimaryTextButton`: Primary text button
- `AppSecondaryTextButton`: Secondary text button
- `AppDangerTextButton`: For destructive actions
- `AppLinkButton`: Link-like behavior

## Feedback Components

### AppErrorContainer

Inline error display with consistent styling.

**Features:**
- Red background with icon and message
- Optional dismiss functionality
- Consistent padding and border radius
- Theme-aware colors

**Usage:**
```dart
if (_errorMessage != null)
  AppErrorContainer(
    message: _errorMessage!,
    onDismiss: () => setState(() => _errorMessage = null),
  )
```

**Variants:**
- `AppFormErrorContainer`: For form errors
- `AppCriticalErrorContainer`: For critical errors

### AppInfoContainer

Info/warning/success messages with different severity levels.

**Features:**
- Multiple severity levels (success, warning, info, neutral)
- Configurable colors
- Optional dismiss functionality
- Theme-aware styling

**Usage:**
```dart
AppInfoContainer(
  message: 'Operation completed successfully',
  type: InfoType.success,
  onDismiss: () => setState(() => _message = null),
)
```

**Variants:**
- `AppSuccessContainer`: Success messages
- `AppWarningContainer`: Warning messages
- `AppInfoMessageContainer`: Info messages

### AppSnackbar

Static helper methods for showing SnackBars.

**Features:**
- Consistent styling across all SnackBars
- RTL support
- Multiple severity levels
- Action support

**Usage:**
```dart
AppSnackbar.showError(context, 'Something went wrong');
AppSnackbar.showSuccess(context, 'Operation completed');
AppSnackbar.showWithRetry(context, 'Failed to load', _retry);
```

### AppLoadingIndicator

Centralized loading indicator with consistent styling.

**Features:**
- Theme-aware colors
- Multiple variants (full-screen, inline, custom)
- Message support
- Customizable size and colors

**Usage:**
```dart
AppLoadingIndicator(
  message: 'Loading...',
  showMessage: true,
)
```

**Variants:**
- `AppFullScreenLoading`: Full-screen loading
- `AppInlineLoading`: Inline loading for buttons
- `AppCustomLoading`: Custom animation
- `AppListLoading`: Loading for lists

### AppEmptyState

Empty state widget for lists/screens.

**Features:**
- Icon, title, subtitle, optional action button
- Theme-aware colors
- Customizable styling
- Multiple specialized variants

**Usage:**
```dart
AppEmptyState(
  title: 'No recipes found',
  subtitle: 'Start by adding your first recipe',
  icon: Icons.restaurant_menu,
  action: ElevatedButton(
    onPressed: _addRecipe,
    child: Text('Add Recipe'),
  ),
)
```

**Variants:**
- `AppNoDataState`: No data scenarios
- `AppNotFoundState`: Not found scenarios
- `AppErrorState`: Error scenarios
- `AppLoadingState`: Loading scenarios
- `AppNoSearchResultsState`: Search results
- `AppEmptyListState`: Empty lists

## Error Handling Service

### ErrorHandlerService

Centralized error handling with user-friendly messages.

**Features:**
- Static methods for error processing
- Multiple error types (API, auth, validation, file, storage)
- Centralized error logging
- Translated error messages

**Usage:**
```dart
try {
  await apiCall();
} catch (e) {
  final error = ErrorHandlerService.logAndHandleError(
    e,
    ref,
    context: 'API call',
    type: ErrorType.api,
  );
  setState(() => _errorMessage = error.userMessage);
}
```

## Theme Integration

All components automatically adapt to the current theme:

- **Light Theme**: Uses `AppTheme.backgroundColor`, `AppTheme.textColor`, etc.
- **Dark Theme**: Uses `AppTheme.darkBackgroundColor`, `AppTheme.darkTextColor`, etc.
- **RTL Support**: Automatic text direction handling for Hebrew/English

## Best Practices

1. **Use components instead of custom widgets** for consistency
2. **Leverage specialized variants** (e.g., `AppDangerButton` for delete actions)
3. **Handle errors consistently** using `ErrorHandlerService`
4. **Test both themes** when using components
5. **Use appropriate feedback components** for different scenarios

## Migration from Existing Code

### Before (login_screen.dart):
```dart
Container(
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    color: isDark ? AppTheme.darkCardColor : AppTheme.backgroundColor,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: isDark ? AppTheme.darkDividerColor : AppTheme.dividerColor),
    boxShadow: [BoxShadow(color: AppTheme.dividerColor.withValues(alpha: 0.04), blurRadius: 8)],
  ),
  child: TextFormField(
    controller: _emailController,
    // ... 40+ lines of configuration
  ),
)
```

### After:
```dart
AppFormContainer(
  child: AppTextField(
    controller: _emailController,
    hintText: AppTranslations.getText(ref, 'email_hint'),
    prefixSvgAsset: 'assets/images/email.svg',
    keyboardType: TextInputType.emailAddress,
    validator: (value) => Helpers.isValidEmail(value) 
        ? null 
        : AppTranslations.getText(ref, 'invalid_email'),
  ),
)
```

## Testing

Each component should be tested for:
- **Widget functionality** in isolation
- **Theme compatibility** (light/dark)
- **RTL support** (Hebrew/English)
- **Accessibility** compliance
- **Error states** and edge cases

## Contributing

When adding new components:
1. Follow the existing naming convention (`AppXxx`)
2. Support both light and dark themes
3. Include RTL support
4. Add comprehensive documentation
5. Include usage examples
6. Test thoroughly

