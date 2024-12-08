module Shared
  module Modals
    class KeyboardShortcutsComponent < ApplicationComponent
      def view_template
        render App::ModalComponent.new(purpose: "help", classes: "modal-lg") do |modal|
          modal.title do
            "Help"
          end
          modal.body do
            table(class: "table") do
              tr do
                th { "Action" }
                th { "Key" }
              end
              tr do
                td { "Navigate through feeds and entries" }
                td do
                  span(class: "key-group") do
                    span(class: "key") { "↑" }
                    span(class: "key") { "↓" }
                    span(class: "key") { "←" }
                    span(class: "key") { "→" }
                  end
                  span(class: "key-group") do
                    span(class: "key") { "j" }
                    span(class: "key") { "k" }
                    span(class: "key") { "h" }
                    span(class: "key") { "l" }
                  end
                end
              end
              tr do
                td { "Page up/down through articles" }
                td do
                  span(class: "key-group") do
                    span(class: "key", title: "page up") { "⇞" }
                    span(class: "key", title: "page down") { "⇟" }
                  end
                end
              end
              tr do
                td { "Navigate through unread items" }
                td { span(class: "key-group") { span(class: "key wide") { "space" } } }
              end
              tr do
                td { "Edit selected feed" }
                td do
                  span(class: "key-group") do
                    span(class: "key wide") { "shift" }
                    span(class: "key") { "e" }
                  end
                end
              end
              tr do
                td { "Expand/collapse tag" }
                td { span(class: "key-group") { span(class: "key") { "e" } } }
              end
              tr do
                td { "Star entry" }
                td { span(class: "key-group") { span(class: "key") { "s" } } }
              end
              tr do
                td { "Toggle read/unread" }
                td { span(class: "key-group") { span(class: "key") { "m" } } }
              end
              tr do
                td { "Open original" }
                td { span(class: "key-group") { span(class: "key") { "v" } } }
              end
              tr do
                td { "Full screen" }
                td do
                  span(class: "key-group") do
                    span(class: "key wide") { "shift" }
                    span(class: "key") { "f" }
                  end
                end
              end
              tr do
                td { "Extract full content" }
                td { span(class: "key-group") { span(class: "key") { "c" } } }
              end
              tr do
                td { "Open sharing menu" }
                td { span(class: "key-group") { span(class: "key") { "f" } } }
              end
              tr do
                td { "Sharing hotkeys" }
                td { span(class: "key-group") { span(class: "key wide") { "1 – 9" } } }
              end
              tr do
                td { "Refresh feeds list" }
                td { span(class: "key-group") { span(class: "key") { "r" } } }
              end
              tr do
                td { "Go to unread" }
                td do
                  span(class: "key-group") do
                    span(class: "key") { "g" }
                    span(class: "spacer") { "then" }
                    span(class: "key") { "u" }
                  end
                end
              end
              tr do
                td { "Go to starred" }
                td do
                  span(class: "key-group") do
                    span(class: "key") { "g" }
                    span(class: "spacer") { "then" }
                    span(class: "key") { "s" }
                  end
                end
              end
              tr do
                td { "Go to all" }
                td do
                  span(class: "key-group") do
                    span(class: "key") { "g" }
                    span(class: "spacer") { "then" }
                    span(class: "key") { "a" }
                  end
                end
              end
              tr do
                td { "Mark all as read" }
                td do
                  span(class: "key-group") do
                    span(class: "key wide") { "shift" }
                    span(class: "key") { "a" }
                  end
                end
              end
              tr do
                td { "Search" }
                td { span(class: "key-group") { span(class: "key") { "/" } } }
              end
              tr do
                td { "Add subscription" }
                td { span(class: "key-group") { span(class: "key") { "a" } } }
              end
              tr do
                td { "Unfocus field" }
                td { span(class: "key-group") { span(class: "key wide") { "escape" } } }
              end
              tr do
                td { "Copy URL of selected article" }
                td do
                  span(class: "key-group") do
                    span(class: "key wide") { "shift" }
                    span(class: "key") { "c" }
                  end
                end
              end
              tr do
                td { "Show help" }
                td { span(class: "key-group") { span(class: "key") { "?" } } }
              end
            end
          end
        end
      end
    end
  end
end

