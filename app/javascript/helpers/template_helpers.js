export function templateText(element, selector, value) {
  let result = element.querySelector(`[data-template~=${selector}]`)
  if (result) {
    result.textContent = value
  } else {
    console.trace(`templateText missing selector: ${selector}`)
  }
}

export function templateHTML(element, selector, value) {
  let result = element.querySelector(`[data-template~=${selector}]`)
  if (result) {
    if (typeof(value) === "object") {
      html(result, value)
    } else {
      result.innerHTML = value
    }
  } else {
    console.trace(`templateHTML missing selector: ${selector}`)
  }
}

export function templateAttribute(element, selector, value, attribute) {
  let result = element.querySelector(selector)
  if (result) {
    result.setAttribute(attribute, value)
  } else {
    console.trace(`templateAttribute missing attribute: ${attribute}`)
  }
}

export function html(target, elements) {
  target.innerHTML = ""
  target.append(...[elements].flat())
}

export function hydrate(element, items) {
  items.forEach((item) => {
    switch (item.type) {
      case "text":
        templateText(element, item.selector, item.value)
        break
      case "html":
        templateHTML(element, item.selector, item.value)
        break
      case "attribute":
        templateAttribute(element, item.selector, item.value, item.attribute)
        break
    }
  })
  return element
}
