name: Bug Report
description: Report a bug or issue
title: "[Bug] "
labels: ["bug"]
body:
  - type: textarea
    attributes:
      label: Description
      description: Clear description of the bug
    validations:
      required: true
  - type: textarea
    attributes:
      label: Steps to Reproduce
      description: Steps to reproduce the behavior
    validations:
      required: true
  - type: input
    attributes:
      label: Expected Behavior
    validations:
      required: true
  - type: input
    attributes:
      label: Actual Behavior
    validations:
      required: true
  - type: input
    attributes:
      label: Environment
      description: OS, app version, device
    validations:
      required: true
  - type: textarea
    attributes:
      label: Screenshots
      description: Add screenshots if applicable
