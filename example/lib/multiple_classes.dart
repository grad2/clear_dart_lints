// Expected: one diagnostic at SecondPublic, private classes are allowed.
class FirstPublic {}

class SecondPublic {
  // Using the private helper avoids unrelated unused-element warnings.
  Object createHelper() {
    return _PrivateHelper();
  }
}

class _PrivateHelper {}
