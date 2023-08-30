# daric-mode.el
Basic Daric language (http://dariclang.com/) support for Emacs.

This package is completely based on fantastic 'basic-mode' package from Johan Dykstrom, available at
https://github.com/dykstrom/basic-mode. I have just adapted it for Daric, but I'm going to move forward with the implementation of Daric specific features.

## Installation
To install manually, place daric-mode.el in your load-path, and add the following lines of code to your init file:

```elisp
(require 'daric-mode)
(autoload 'daric-generic-mode "daric-mode" "Major mode for editing Daric code." t)
(add-to-list 'auto-mode-alist '("\\.daric\\'" . daric-generic-mode))
(add-hook 'daric-mode-hook #'custom-daric-hook)
(add-hook 'daric-generic-mode-hook #'custom-daric-hook)
(defun custom-daric-hook ()
  (setq indent-tabs-mode nil)
  (message "Hello to Daric mode!"))
```
